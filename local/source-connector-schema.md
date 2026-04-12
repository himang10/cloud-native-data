# Debezium Connector 스키마 히스토리 설정 가이드

## 개요

### Schema와 Schema History란?

Debezium MySQL/MariaDB 커넥터는 데이터베이스의 **테이블 스키마 정보**를 추적하고 관리해야 합니다. 이는 **binlog의 바이너리 데이터를 파싱하여 의미있는 JSON 메시지로 변환**하기 위해 필수적입니다.

#### Schema (스키마)
- **정의**: 데이터베이스 테이블의 구조 정보 (컬럼명, 데이터 타입, 제약조건 등)
- **역할**: binlog의 바이너리 데이터를 읽어서 JSON 메시지로 변환하는 "파싱 규칙"
- **핵심 원리**: 
  - binlog는 바이너리 형식으로 데이터 저장 (예: `0x00000001`, `0x4A6F686E`)
  - 스키마 정보가 있어야 이것을 파싱 가능 (예: `id=1`, `name="John"`)
- **예시**:
  ```sql
  CREATE TABLE outbox_events (
    id VARCHAR(36) PRIMARY KEY,        -- 컬럼1: 문자열, 최대 36자
    aggregate_type VARCHAR(255),       -- 컬럼2: 문자열, 최대 255자
    aggregate_id VARCHAR(36),          -- 컬럼3: 문자열, 최대 36자
    type VARCHAR(255),                 -- 컬럼4: 문자열, 최대 255자
    payload JSON,                      -- 컬럼5: JSON 타입
    timestamp TIMESTAMP                -- 컬럼6: 타임스탬프
  );
  ```

#### Schema History (스키마 히스토리)
- **정의**: 시간에 따른 스키마 변경 이력(DDL)을 기록한 것
- **저장 내용**: DDL(Data Definition Language) 문 (CREATE, ALTER, DROP 등)
- **저장 위치**: Kafka 내부 토픽 (예: `mariadb.dbhistory.outbox-server`)
- **핵심 동작 원리**:
  1. **DDL 감지 시**: binlog에서 ALTER TABLE 등 DDL 감지 → 스키마 히스토리 토픽에 저장 → 메모리의 파싱 규칙 업데이트
  2. **CUD 파싱 시**: binlog의 INSERT/UPDATE/DELETE 바이너리 데이터 → 현재 스키마 규칙으로 파싱 → JSON 메시지 생성 → Kafka 토픽 전송
  3. **재시작 시**: 스키마 히스토리 토픽 읽기 → 모든 DDL 재적용 → 파싱 규칙 복원 → binlog 파싱 재개
- **목적**: 
  1. 커넥터 재시작 시 현재 스키마 상태 복원 (파싱 규칙 재구성)
  2. 과거 binlog 위치부터 재개할 때 당시의 스키마 적용 (올바른 파싱)
  3. 데이터 타입 변환 규칙 유지 (일관된 메시지 형식)

### 왜 스키마 히스토리가 필요한가?

#### 문제 상황 1: 스키마 변경 후 재시작 (파싱 규칙 복원 실패)

```sql
-- ========================================
-- T1 시점: 초기 스키마 생성 및 데이터 추가
-- ========================================
CREATE TABLE outbox_events (
  id VARCHAR(36),
  payload JSON
);

-- 커넥터 시작 → 스키마 히스토리 토픽에 CREATE DDL 저장
-- mariadb.dbhistory.outbox-server 토픽 메시지:
-- {
--   "ddl": "CREATE TABLE outbox_events (id VARCHAR(36), payload JSON)",
--   "tableChanges": [
--     {"type": "CREATE", "columns": [
--       {"name": "id", "type": "VARCHAR(36)"},
--       {"name": "payload", "type": "JSON"}
--     ]}
--   ]
-- }

-- 메모리의 파싱 규칙:
-- outbox_events = [컬럼1: id(VARCHAR), 컬럼2: payload(JSON)]

INSERT INTO outbox_events VALUES ('uuid-1', '{"data": "test1"}');
-- binlog 바이너리: [0x756964-31] [0x7B2264617461...]
-- 파싱 결과: {"id": "uuid-1", "payload": {"data": "test1"}}
-- Kafka 전송 완료

-- ========================================
-- T2 시점: 스키마 변경 (컬럼 추가)
-- ========================================
ALTER TABLE outbox_events ADD COLUMN version INT DEFAULT 1;

-- 커넥터 감지 → 스키마 히스토리 토픽에 ALTER DDL 추가 저장
-- mariadb.dbhistory.outbox-server 토픽 메시지 (추가):
-- {
--   "ddl": "ALTER TABLE outbox_events ADD COLUMN version INT DEFAULT 1",
--   "tableChanges": [
--     {"type": "ALTER", "columns": [
--       {"name": "id", "type": "VARCHAR(36)"},
--       {"name": "payload", "type": "JSON"},
--       {"name": "version", "type": "INT"}  ← 새로 추가
--     ]}
--   ]
-- }

-- 메모리의 파싱 규칙 업데이트:
-- outbox_events = [컬럼1: id(VARCHAR), 컬럼2: payload(JSON), 컬럼3: version(INT)]

INSERT INTO outbox_events VALUES ('uuid-2', '{"data": "test2"}', 1);
-- binlog 바이너리: [0x756964-32] [0x7B2264617461...] [0x00000001]
-- 파싱 결과: {"id": "uuid-2", "payload": {"data": "test2"}, "version": 1}
-- Kafka 전송 완료

-- ========================================
-- T3 시점: 커넥터 재시작
-- ========================================

-- ❌ 스키마 히스토리 없으면:
-- 1. 커넥터는 현재 DB 스키마만 조회 가능
-- 2. 하지만 DB는 현재 상태(3개 컬럼)만 알려줌
-- 3. 메모리 파싱 규칙: outbox_events = [id, payload, version]
-- 4. 문제: binlog의 과거 데이터(2개 컬럼)도 이 규칙으로 파싱 시도
--    → T1 시점 binlog 재처리 시 파싱 오류!

-- ✅ 스키마 히스토리 있으면:
-- 1. 커넥터 재시작
-- 2. schema.history.internal.kafka.topic 읽기 시작
-- 3. 첫 번째 메시지: CREATE DDL
--    → 메모리 파싱 규칙: [id, payload]
-- 4. 두 번째 메시지: ALTER DDL
--    → 메모리 파싱 규칙 업데이트: [id, payload, version]
-- 5. binlog 읽기 재개:
--    - T1 시점 binlog (2개 컬럼) → CREATE 당시 규칙으로 파싱 ✓
--    - T2 시점 binlog (3개 컬럼) → ALTER 이후 규칙으로 파싱 ✓
--
-- binlog position에 따라 적절한 파싱 규칙 자동 적용!

-- 재시작 후 새 데이터 추가:
INSERT INTO outbox_events VALUES ('uuid-3', '{"data": "test3"}', 1);
-- binlog 바이너리: [0x756964-33] [0x7B2264617461...] [0x00000001]
-- 복원된 파싱 규칙 적용: {"id": "uuid-3", "payload": {"data": "test3"}, "version": 1}
-- Kafka 전송 완료 ✓
```

**핵심 이해**:
1. **스키마 히스토리 = DDL 시간 순서대로 저장된 파싱 규칙 변경 로그**
2. **재시작 시 = 모든 DDL을 순서대로 다시 적용하여 현재 파싱 규칙 재구성**
3. **binlog 파싱 = 각 binlog position의 데이터를 그 시점의 스키마로 파싱**
4. **스키마 히스토리 없으면 = 현재 DB 스키마로 과거 binlog 파싱 시도 → 오류**

#### 문제 상황 2: 과거 binlog부터 재개 (잘못된 파싱 규칙 적용)
```
1. 커넥터가 binlog position 1000까지 처리 (schema v1: 2개 컬럼)
   binlog @ position 800:
     INSERT → [0x756964-31] [0x7B...]
     파싱 → {"id": "uuid-1", "payload": {...}}

2. ALTER TABLE 실행 (schema v2: 3개 컬럼 추가)
   binlog @ position 2000:
     ALTER TABLE ADD COLUMN version INT;

3. 커넥터 장애로 중단

4. 재시작 시 position 1000부터 재개
   binlog @ position 1500 (v1 스키마 시절 데이터):
     INSERT → [0x756964-35] [0x7B...] (2개 컬럼만 존재)
   
   ❌ 현재 DB 스키마 사용 (v2: 3개 컬럼 규칙):
      2개 컬럼 데이터를 3개 컬럼 규칙으로 파싱 시도
      → 파싱 오류: "Expected 3 columns but got 2"
      → 커넥터 FAILED
   
   ✅ 스키마 히스토리 사용:
      스키마 히스토리에서 position 1500 당시 스키마 확인 (v1: 2개 컬럼)
      2개 컬럼 규칙으로 파싱
      → {"id": "uuid-35", "payload": {...}} (정상!)
      
      position 2000 도달 시:
      ALTER DDL 감지 → 파싱 규칙 v2로 업데이트
      이후 3개 컬럼 데이터를 3개 컬럼 규칙으로 파싱
```

#### 문제 상황 3: 멀티 커넥터 환경
```
두 개의 커넥터가 같은 데이터베이스 사용:
- outbox-connector: outbox_events 테이블만 캡처
- cdc-connector: users, orders 테이블 캡처

각 커넥터는 독립된 스키마 히스토리 토픽 사용:
- mariadb.dbhistory.outbox-server
- mariadb.dbhistory.cdc-server

이유:
1. 서로 다른 테이블 추적 → 다른 DDL 이력
2. 독립적인 재시작 가능
3. 스키마 충돌 방지
```

### 스키마 히스토리 동작 흐름 (binlog 파싱 과정)

```
[커넥터 시작]
   ↓
[1] schema.history.internal.kafka.topic 읽기
   → 저장된 모든 DDL 이력 로드 (CREATE, ALTER 등)
   → 메모리에 현재 스키마 파싱 규칙 재구성
   예: outbox_events 테이블 = [id(VARCHAR), type(VARCHAR), payload(JSON) ...]
   ↓
[2] 마지막 binlog position 확인
   예: mysql-bin.000003, position 5432
   ↓
[3] binlog 읽기 시작
   ↓
[4-A] DDL 이벤트 감지 (스키마 변경)
   binlog: ALTER TABLE outbox_events ADD COLUMN version INT;
   ↓
   → schema.history.internal.kafka.topic에 DDL 저장
   → 메모리의 파싱 규칙 업데이트
   예: outbox_events = [...기존 컬럼..., version(INT)]
   ↓
[4-B] DML 이벤트 감지 (데이터 변경)
   binlog 바이너리 데이터:
     Table_id: 108 (outbox_events)
     Columns: 6개 값의 바이트 배열
     [0x756964-31, 0x4F72646572, 0x6F72646572-31, 0x4372656174, 0x7B226F72...], 0x313732...]
   ↓
   → 현재 스키마 파싱 규칙 적용
   컬럼1 (VARCHAR 36자) = "uuid-1"
   컬럼2 (VARCHAR 255자) = "Order"
   컬럼3 (VARCHAR 36자) = "order-1"
   컬럼4 (VARCHAR 255자) = "OrderCreated"
   컬럼5 (JSON) = {"orderId": "123", ...}
   컬럼6 (TIMESTAMP) = "2024-01-15T10:30:00Z"
   ↓
   → JSON 메시지 생성
   {
     "before": null,
     "after": {
       "id": "uuid-1",
       "aggregate_type": "Order",
       "aggregate_id": "order-1",
       "type": "OrderCreated",
       "payload": "{\"orderId\": \"123\", ...}",
       "timestamp": 1705315800000
     },
     "op": "c"
   }
   ↓
   → Kafka 토픽 전송 (mariadb-outbox.cloud.outbox_events)
```

**핵심 포인트**:
1. **스키마 = binlog 바이너리 데이터의 파싱 규칙**
2. **스키마 히스토리 = DDL 변경 이력을 저장하여 파싱 규칙을 지속적으로 업데이트**
3. **CUD 메시지 파싱 = 현재 메모리의 스키마 규칙으로 binlog 바이너리 → JSON 변환**
4. **재시작 시 = 스키마 히스토리 토픽의 모든 DDL을 다시 적용하여 파싱 규칙 복원**

### 스키마 히스토리 저장 예시

**Kafka 토픽 내용**:
```json
{
  "source": {
    "server": "mariadb-outbox-source-server"
  },
  "position": {
    "file": "mysql-bin.000003",
    "pos": 154,
    "gtids": null
  },
  "ts_ms": 1699200000000,
  "databaseName": "cloud",
  "ddl": "CREATE TABLE outbox_events (id VARCHAR(36) PRIMARY KEY, aggregate_type VARCHAR(255), aggregate_id VARCHAR(36), type VARCHAR(255), payload JSON, timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP)",
  "tableChanges": [
    {
      "type": "CREATE",
      "id": "\"cloud\".\"outbox_events\"",
      "table": {
        "defaultCharsetName": "utf8mb4",
        "primaryKeyColumnNames": ["id"],
        "columns": [
          {
            "name": "id",
            "jdbcType": 12,
            "typeName": "VARCHAR",
            "typeExpression": "VARCHAR",
            "charsetName": "utf8mb4",
            "length": 36
          },
          {
            "name": "payload",
            "jdbcType": 2005,
            "typeName": "JSON",
            "typeExpression": "JSON"
          }
        ]
      }
    }
  ]
}
```

---

## 스키마 히스토리 설정 필드

### schema.history.internal.kafka.bootstrap.servers

#### 기본 정보
- **값**: `"kafka:9092"`
- **타입**: String
- **필수**: Yes
- **형식**: `host:port` 또는 `host1:port1,host2:port2`

#### 상세 설명

**정의**: 스키마 변경 이력(DDL)을 저장할 Kafka 클러스터의 주소입니다.

**용도**:
- Debezium이 binlog에서 감지한 DDL 변경 이력을 Kafka 내부 토픽에 저장
- 커넥터 재시작 시 모든 DDL을 다시 적용하여 binlog 파싱 규칙 복원
- binlog 바이너리 데이터 → JSON 메시지 변환 규칙 유지

**예시**:
```json
// 단일 브로커
"schema.history.internal.kafka.bootstrap.servers": "kafka:9092"

// 다중 브로커 (고가용성)
"schema.history.internal.kafka.bootstrap.servers": "kafka1:9092,kafka2:9092,kafka3:9092"

// 외부 주소
"schema.history.internal.kafka.bootstrap.servers": "my-kafka-cluster.example.com:9092"
```

**설정값에 따른 동작**:

| 환경 | 설정 | 용도 |
|------|------|------|
| Docker Compose | `kafka:9092` | 컨테이너 네트워크 내부 이름 |
| Kubernetes | `my-kafka-cluster-kafka-bootstrap:9092` | Kubernetes Service 이름 |
| 외부 Kafka | `external-kafka.cloud:9092` | 외부 클러스터 주소 |

**주의사항**:
1. **네트워크 접근성**: 커넥터가 이 주소로 접속 가능해야 함
2. **방화벽**: 포트 9092 열려 있어야 함
3. **DNS 해석**: 호스트명이 정확히 해석되어야 함

**확인 방법**:
```bash
# 연결 테스트
docker exec kafka-connect-debezium \
  nc -zv kafka 9092

# 토픽 확인
docker exec kafka kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --list | grep dbhistory
```

### schema.history.internal.kafka.topic

#### 기본 정보
- **값**: `"mariadb.dbhistory.outbox-server"`
- **타입**: String
- **필수**: Yes

#### 상세 설명

**정의**: DDL 변경 이력을 저장할 Kafka 내부 토픽 이름입니다.

**용도**:
- CREATE TABLE, ALTER TABLE 등 DDL 문 저장 (binlog 파싱 규칙의 변경 이력)
- 커넥터 재시작 시 모든 DDL을 순차 적용하여 binlog 파싱 규칙 재구성
- 여러 커넥터 간 격리 (각 커넥터가 독립된 파싱 규칙 유지)

**네이밍 패턴**:
```
{database}.dbhistory.{purpose}
```

**예시**:
```json
// Outbox 커넥터
"schema.history.internal.kafka.topic": "mariadb.dbhistory.outbox-server"

// CDC 커넥터
"schema.history.internal.kafka.topic": "mariadb.dbhistory.cdc-server"

// 환경별 구분
"schema.history.internal.kafka.topic": "prod-mariadb.dbhistory.outbox"
```

**토픽 특성**:
- **파티션**: 1 (순서 보장 필요)
- **보존 정책**: 무제한 (compact + delete)
- **복제 계수**: 3 (프로덕션)

**설정값에 따른 동작**:

##### 시나리오 1: 독립된 히스토리
```json
// Outbox 커넥터
{
  "schema.history.internal.kafka.topic": "mariadb.dbhistory.outbox-server"
}

// CDC 커넥터
{
  "schema.history.internal.kafka.topic": "mariadb.dbhistory.cdc-server"
}
```
**결과**: 각 커넥터가 독립적인 스키마 히스토리 유지

##### 시나리오 2: 공유 히스토리 (비권장)
```json
// 두 커넥터가 같은 토픽 사용
{
  "schema.history.internal.kafka.topic": "mariadb.dbhistory.shared"
}
```
**결과**: 충돌 가능, 스키마 정보 혼재

**토픽 내용 예시**:
```json
{
  "source": {
    "server": "mariadb-outbox-source-server"
  },
  "position": {
    "file": "mysql-bin.000003",
    "pos": 154
  },
  "databaseName": "cloud",
  "ddl": "CREATE TABLE outbox_events (...)",
  "tableChanges": [...]
}
```

**확인 방법**:
```bash
# 토픽 존재 확인
docker exec kafka kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --describe --topic mariadb.dbhistory.outbox-server

# 내용 확인 (처음 10개)
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic mariadb.dbhistory.outbox-server \
  --from-beginning \
  --max-messages 10
```

### schema.history.internal.store.only.captured.tables.ddl

#### 기본 정보
- **값**: `"true"`
- **타입**: Boolean (문자열)
- **기본값**: `false`
- **필수**: No

#### 상세 설명

**정의**: 캡처 대상 테이블의 DDL만 스키마 히스토리에 저장할지 여부를 결정합니다.

**용도**:
- 불필요한 DDL 저장 방지 (파싱하지 않을 테이블의 binlog 파싱 규칙 제외)
- 스키마 히스토리 토픽 크기 감소 (필요한 파싱 규칙만 저장)
- 파싱 오류 가능성 감소 (복잡한 DDL 제외)

**설정값에 따른 동작**:

##### `"true"` (권장)
```json
{
  "table.include.list": "cloud.outbox_events",
  "schema.history.internal.store.only.captured.tables.ddl": "true"
}
```

**동작**:
- `cloud.outbox_events` 테이블 DDL만 저장
- 다른 테이블의 DDL 무시

**저장되는 DDL**:
```sql
-- 저장됨
CREATE TABLE outbox_events (...);
ALTER TABLE outbox_events ADD COLUMN version INT;

-- 저장 안 됨
CREATE TABLE users (...);
ALTER TABLE orders ADD INDEX idx_user;
```

**장점**:
1. 스키마 히스토리 토픽 크기 최소화
2. 복잡한 DDL 파싱 오류 회피
3. 커넥터 재시작 속도 향상

##### `"false"` (기본값)
```json
{
  "schema.history.internal.store.only.captured.tables.ddl": "false"
}
```

**동작**:
- 모든 데이터베이스의 모든 DDL 저장
- 캡처 대상 아닌 테이블 DDL도 포함

**저장되는 DDL**:
```sql
-- 모두 저장됨
CREATE TABLE outbox_events (...);
CREATE TABLE users (...);
CREATE TABLE orders (...);
ALTER TABLE products ADD COLUMN price DECIMAL;
```

**단점**:
1. 스키마 히스토리 토픽 용량 증가
2. 복잡한 DDL 파싱 실패 가능
3. 재시작 시 불필요한 DDL 처리

**실제 시나리오**:

##### 시나리오 1: Outbox 전용 (true 권장)
```json
{
  "database.include.list": "cloud",
  "table.include.list": "cloud.outbox_events",
  "schema.history.internal.store.only.captured.tables.ddl": "true"
}
```

**cloud 데이터베이스**:
- outbox_events (캡처 대상)
- users (캡처 대상 아님)
- orders (캡처 대상 아님)
- products (캡처 대상 아님)

**결과**:
- outbox_events DDL만 히스토리 저장
- 나머지 테이블 DDL 무시
- 파싱 오류 위험 감소

##### 시나리오 2: 멀티 테이블 CDC (false 가능)
```json
{
  "table.include.list": "cloud.users,cloud.orders,cloud.products",
  "schema.history.internal.store.only.captured.tables.ddl": "false"
}
```

**이유**:
- 여러 테이블 관계 추적 필요
- 외래키 제약조건 이해 필요
- 전체 스키마 컨텍스트 유지

**Outbox Pattern 권장**:
```json
{
  "schema.history.internal.store.only.captured.tables.ddl": "true"
}
```

**이유**:
1. Outbox는 단일 테이블만 캡처
2. 다른 테이블 DDL 불필요
3. 안정성 향상

### schema.history.internal.skip.unparseable.ddl

#### 기본 정보
- **값**: `"true"`
- **타입**: Boolean (문자열)
- **기본값**: `false`
- **필수**: No (하지만 강력 권장)

#### 상세 설명

**정의**: Debezium이 파싱할 수 없는 DDL 문을 만났을 때 에러 없이 건너뛰고 계속 진행할지 결정합니다.

**용도**:
- 복잡한 MariaDB/MySQL 특화 DDL의 파싱 규칙 생성 실패 시에도 계속 진행
- 커넥터 안정성 향상 (파싱 불가 DDL로 인한 중단 방지)
- binlog CUD 메시지 파싱은 계속 수행 (DDL 파싱 실패와 무관)

**파싱 불가능한 DDL 예시**:

```sql
-- 1. 복잡한 파티션
CREATE TABLE orders (
  id INT,
  order_date DATE
) PARTITION BY RANGE (YEAR(order_date)) (
  PARTITION p0 VALUES LESS THAN (2020),
  PARTITION p1 VALUES LESS THAN (2021)
);

-- 2. 특수 인덱스
CREATE FULLTEXT INDEX ft_search ON articles(title, content);
CREATE INDEX idx_hash ON users(email) USING HASH;

-- 3. MariaDB 버전 관리
CREATE TABLE audit_log (...) WITH SYSTEM VERSIONING;

-- 4. 복잡한 외래키
ALTER TABLE orders ADD CONSTRAINT fk_complex
FOREIGN KEY (user_id) REFERENCES users(id)
ON DELETE CASCADE ON UPDATE SET NULL;

-- 5. 스토어드 프로시저/함수
CREATE FUNCTION calculate_total(...)
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
  -- 복잡한 로직
END;
```

**설정값에 따른 동작**:

##### `"true"` (권장)
```json
"schema.history.internal.skip.unparseable.ddl": "true"
```

**동작 흐름**:
```
1. Debezium이 binlog에서 DDL 감지
2. DDL 파싱 시도
3. 파싱 실패
   → WARNING 로그 출력
   → 해당 DDL 건너뛰기
   → 다음 이벤트 계속 처리
4. 커넥터 상태: RUNNING 유지
```

**로그 예시**:
```
WARN: Could not parse DDL statement: CREATE TABLE test (...) PARTITION BY ...
WARN: Skipping unparseable DDL statement
INFO: Continuing with next binlog event
```

**장점**:
1. 커넥터 중단 방지
2. 프로덕션 안정성
3. 복잡한 DDL 환경 대응

##### `"false"` (기본값, 위험)
```json
"schema.history.internal.skip.unparseable.ddl": "false"
```

**동작 흐름**:
```
1. Debezium이 binlog에서 DDL 감지
2. DDL 파싱 시도
3. 파싱 실패
   → ERROR 발생
   → 커넥터 FAILED 상태로 전환
   → CDC 중단
4. 수동 개입 필요
```

**에러 예시**:
```
ERROR: Failed to parse DDL statement: CREATE TABLE test (...)
ERROR: io.debezium.text.ParsingException: ...
ERROR: Connector status changed to FAILED
```

**영향**:
- Outbox 이벤트 전송 중단
- 비즈니스 로직 영향
- 긴급 대응 필요

**실제 시나리오**:

##### 시나리오 1: 복잡한 DB 환경 (true 필수)
```sql
-- cloud 데이터베이스
CREATE TABLE outbox_events (...);  -- 단순 DDL
CREATE TABLE users (...) PARTITION BY HASH(id);  -- 복잡한 DDL
CREATE FULLTEXT INDEX ft_search ON logs(message);  -- 특수 인덱스
```

**설정**:
```json
{
  "database.include.list": "cloud",
  "table.include.list": "cloud.outbox_events",
  "schema.history.internal.store.only.captured.tables.ddl": "true",
  "schema.history.internal.skip.unparseable.ddl": "true"
}
```

**결과**:
- outbox_events DDL: 정상 파싱
- users PARTITION DDL: 건너뜀 (캡처 대상 아님 + skip=true)
- ft_search INDEX: 건너뜀 (캡처 대상 아님 + skip=true)
- 커넥터: 계속 동작

##### 시나리오 2: false 설정 시 실패
```json
{
  "schema.history.internal.skip.unparseable.ddl": "false"
}
```

**같은 환경에서**:
- users PARTITION DDL 파싱 실패
- 커넥터 FAILED
- Outbox 이벤트 전송 중단

**복구 방법**:
```bash
# 1. 커넥터 삭제
./delete-connector.sh mariadb-outbox-connector

# 2. 설정 수정 (skip=true)
# mariadb-outbox-connector.json 편집

# 3. 재등록
./register-connector.sh mariadb-outbox-connector.json
```

**관련 설정 조합 (최적)**:

```json
{
  "database.include.list": "cloud",
  "table.include.list": "cloud.outbox_events",
  "include.schema.changes": "false",
  
  "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
  "schema.history.internal.kafka.topic": "mariadb.dbhistory.outbox-server",
  "schema.history.internal.store.only.captured.tables.ddl": "true",
  "schema.history.internal.skip.unparseable.ddl": "true"
}
```

**이 조합의 효과**:
1. Outbox 테이블만 추적
2. DDL 이벤트 Kafka 미전송
3. 캡처 대상 DDL만 저장
4. 파싱 실패 시 건너뛰기
5. 최대 안정성 보장

**모니터링**:
```bash
# 경고 로그 확인
docker logs kafka-connect-debezium 2>&1 | grep -i "unparseable"

# 커넥터 상태 확인
./check-connector.sh mariadb-outbox-connector
```

**주의사항**:
1. **프로덕션 필수**: 반드시 `"true"` 설정
2. **로그 모니터링**: WARNING 로그 추적하여 파싱 실패 DDL 파악
3. **영향 없음**: Outbox 테이블 DDL은 단순하므로 파싱 성공

---

## 참고 자료

- [Debezium MySQL Connector 공식 문서](https://debezium.io/documentation/reference/stable/connectors/mysql.html)
- [Debezium Schema History 공식 문서](https://debezium.io/documentation/reference/stable/connectors/mysql.html#mysql-schema-history-topic)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)

---

**문서 버전**: 1.0  
**최종 업데이트**: 2025-11-16
