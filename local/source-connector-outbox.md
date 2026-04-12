# Debezium Outbox Connector 전용 설정 필드 가이드

이 문서는 Outbox Pattern 구현을 위한 Debezium 커넥터의 전용 설정 필드를 설명합니다.

**다른 문서 참조**:
- [공통 설정 필드](./connector-field-common.md): name, connector.class, tasks.max, database 연결 설정
- [스키마 히스토리 설정](./connector-field-schema.md): schema.history.* 필드

---

## 1. database.server.id

### 기본 정보
- **값**: `"284059"` (예시)
- **타입**: String (숫자)
- **필수**: Yes
- **고유성**: 필수

### 상세 설명

#### 정의
MySQL/MariaDB 복제 클라이언트 ID입니다. 데이터베이스 서버는 각 복제 클라이언트를 이 ID로 식별하며, Debezium은 binlog를 읽기 위해 복제 클라이언트로 동작합니다.

#### 사용 용도

##### 1. Binlog 스트리밍 식별
```sql
-- MariaDB에서 현재 연결된 복제 클라이언트 확인
SHOW SLAVE HOSTS;

+------------+------+------+-----------+--------------------------------------+
| Server_id  | Host | Port | Master_id | Slave_UUID                           |
+------------+------+------+-----------+--------------------------------------+
| 284059     | ...  | ...  | 1         | debezium-connector-uuid              |
+------------+------+------+-----------+--------------------------------------+
```

##### 2. Binlog Position 추적
- 각 server.id별로 어디까지 읽었는지 독립적으로 관리
- 커넥터 재시작 시 이전 위치부터 재개

##### 3. 충돌 방지
- 동일 MariaDB 서버에 여러 Debezium 커넥터 연결 시 **반드시 다른 ID** 사용

#### 설정값에 따른 동작

##### ✅ 올바른 사용 (고유 ID)
```json
// Outbox 커넥터
{
  "database.server.id": "284059",
  "topic.prefix": "mariadb-outbox-source-server"
}

// CDC 커넥터 (동일 DB, 다른 테이블)
{
  "database.server.id": "284060",  // ← 다른 ID
  "topic.prefix": "mariadb-cdc"
}
```

**결과**: 
- ✅ 두 커넥터가 독립적으로 binlog 스트리밍
- ✅ 각각 다른 오프셋 유지
- ✅ 서로 영향 없음

##### ❌ 잘못된 사용 (중복 ID)
```json
// Outbox 커넥터
{
  "database.server.id": "284059",
  ...
}

// CDC 커넥터 (같은 ID 사용)
{
  "database.server.id": "284059",  // ← 중복!
  ...
}
```

**결과**:
- ❌ Binlog position 충돌
- ❌ 커넥터 중 하나가 실패하거나 불안정
- ❌ 이벤트 누락 또는 중복 발생 가능

#### ID 선택 가이드

**권장 방법:**
1. 큰 숫자 사용 (충돌 회피): `200000` ~ `299999`
2. 커넥터 용도별 범위 할당:
   - Outbox: `284000` ~ `284099`
   - CDC: `284100` ~ `284199`
   - Audit: `284200` ~ `284299`

**확인 방법:**
```sql
-- 현재 사용 중인 server_id 확인
SHOW VARIABLES LIKE 'server_id';

-- 복제 클라이언트 목록
SHOW SLAVE HOSTS;
```

#### 실제 시나리오

##### 시나리오 1: 단일 커넥터
```json
{
  "database.server.id": "284059"
}
```
- ✅ 문제 없음
- 유일한 복제 클라이언트

##### 시나리오 2: 멀티 커넥터 (같은 DB)
```json
// outbox-connector
{"database.server.id": "284059"}

// users-cdc-connector
{"database.server.id": "284060"}

// orders-cdc-connector
{"database.server.id": "284061"}
```
- ✅ 각 커넥터가 독립적으로 binlog 읽기
- 서로 다른 테이블 캡처 가능

##### 시나리오 3: 다중 환경
```json
// DEV
{"database.server.id": "284059"}

// STAGING (같은 MariaDB 공유 시)
{"database.server.id": "284159"}

// PROD
{"database.server.id": "284259"}
```

### 주의사항

1. **절대 중복 금지**: 같은 DB에 연결하는 커넥터는 고유 ID 필수
2. **재사용 주의**: 커넥터 삭제 후 즉시 같은 ID 재사용 시 오프셋 충돌 가능
3. **마스터 ID와 구분**: DB 자체의 `server_id`(보통 1)와 다른 값 사용

---

## 2. topic.prefix

### 기본 정보
- **값**: `"mariadb-outbox-source-server"` (예시)
- **타입**: String
- **필수**: Yes

### 상세 설명

#### 정의
Debezium이 생성하는 내부 토픽 및 표준 CDC 토픽의 접두어입니다. Outbox Pattern에서는 EventRouter가 별도 토픽(`outbox.*`)을 생성하지만, 내부 메타데이터 토픽은 이 prefix를 사용합니다.

#### 사용되는 곳

##### 1. 스키마 히스토리 토픽
```
{topic.prefix}.dbhistory.{suffix}
```

**예시:**
```
mariadb-outbox-source-server.dbhistory.outbox-server
```

**용도:**
- DDL 변경 이력 저장
- 커넥터 재시작 시 스키마 복원

##### 2. 표준 CDC 토픽 (Outbox는 미사용)
```
{topic.prefix}.{database}.{table}
```

**예시:**
```
mariadb-outbox-source-server.cloud.outbox_events
```

**참고**: Outbox EventRouter 사용 시 이 토픽은 생성되지 않고, 대신 `outbox.{aggregate_type}` 토픽이 생성됩니다.

##### 3. 서버 하트비트 토픽 (선택사항)
```
{topic.prefix}.heartbeat
```

**용도:**
- Binlog가 오래 idle 상태일 때 커넥터 활성 유지

#### 설정값에 따른 동작

##### 예시 1: Outbox 전용 Prefix
```json
{
  "topic.prefix": "mariadb-outbox-source-server",
  "schema.history.internal.kafka.topic": "mariadb.dbhistory.outbox-server"
}
```

**생성 토픽:**
- `mariadb.dbhistory.outbox-server` (스키마 히스토리)
- `outbox.user` (EventRouter)
- `outbox.order` (EventRouter)
- `outbox.product` (EventRouter)

##### 예시 2: CDC 전용 Prefix
```json
{
  "topic.prefix": "mariadb-cdc",
  "table.include.list": "cloud.users,cloud.orders"
}
```

**생성 토픽:**
- `mariadb-cdc.cloud.users` (표준 CDC)
- `mariadb-cdc.cloud.orders` (표준 CDC)
- `mariadb-cdc.dbhistory` (스키마 히스토리)

#### 네이밍 가이드

**권장 패턴:**
```
{env}-{database}-{purpose}-server
```

**예시:**
- `prod-mariadb-outbox-server`
- `dev-mysql-cdc-server`
- `staging-db-audit-server`

**장점:**
- 환경/용도 구분 명확
- 토픽 검색/관리 용이
- 여러 데이터베이스 운영 시 충돌 방지

#### 실제 시나리오

##### 시나리오 1: 단일 Outbox 커넥터
```json
{
  "topic.prefix": "mariadb-outbox-source-server",
  "transforms": "outbox"
}
```

**결과:**
- 비즈니스 토픽: `outbox.*` (EventRouter)
- 메타 토픽: `mariadb-outbox-source-server.*`

##### 시나리오 2: Outbox + CDC 혼합
```json
// Outbox 커넥터
{
  "topic.prefix": "mariadb-outbox",
  "table.include.list": "cloud.outbox_events"
}

// CDC 커넥터
{
  "topic.prefix": "mariadb-cdc",
  "table.include.list": "cloud.users,cloud.orders"
}
```

**결과:**
- Outbox 토픽: `outbox.user`, `outbox.order`
- CDC 토픽: `mariadb-cdc.cloud.users`, `mariadb-cdc.cloud.orders`
- 히스토리 토픽: 각각 독립적으로 생성

### database.server.id와 topic.prefix 관계

| 항목 | database.server.id | topic.prefix |
|------|-------------------|--------------|
| **범위** | 데이터베이스 레벨 | Kafka 레벨 |
| **고유성** | DB 서버당 고유 | Connect 클러스터당 고유 |
| **용도** | Binlog 클라이언트 식별 | 토픽 네이밍 |
| **충돌 시** | Binlog 스트리밍 실패 | 토픽 덮어쓰기 위험 |
| **변경 영향** | 오프셋 초기화 | 토픽 재생성 |

**모범 사례:**
- 두 값 모두 환경별로 다르게 설정
- 명확한 네이밍 컨벤션 수립
- 변경 시 영향 범위 사전 파악

### 설정 예시 비교

#### 개발 환경
```json
{
  "name": "dev-outbox-connector",
  "database.server.id": "284059",
  "topic.prefix": "dev-mariadb-outbox"
}
```

#### 프로덕션 환경
```json
{
  "name": "prod-outbox-connector",
  "database.server.id": "384059",
  "topic.prefix": "prod-mariadb-outbox"
}
```

---

## 3. 캡처 대상 설정

### database.include.list

#### 기본 정보
- **값**: `"cloud"`
- **타입**: String (쉼표로 구분된 목록)
- **필수**: No (하지만 권장)

#### 상세 설명

**정의**: Debezium이 캡처할 데이터베이스(스키마) 목록을 지정합니다. 화이트리스트 방식으로 동작합니다.

**용도**:
- 특정 데이터베이스만 CDC 대상으로 제한
- 불필요한 데이터베이스의 binlog 이벤트 필터링
- 시스템 데이터베이스(mysql, information_schema) 자동 제외

**예시**:
```json
// 단일 데이터베이스
"database.include.list": "cloud"

// 복수 데이터베이스
"database.include.list": "cloud,app,orders"
```

**설정값에 따른 동작**:

| 설정 | 동작 |
|------|------|
| `"cloud"` | cloud 데이터베이스만 캡처 |
| `"cloud,app"` | cloud와 app 데이터베이스 캡처 |
| 미설정 | 모든 데이터베이스 캡처 (비권장) |

**Outbox Pattern 권장 설정**:
```json
{
  "database.include.list": "cloud",
  "table.include.list": "cloud.outbox_events"
}
```

### table.include.list

#### 기본 정보
- **값**: `"cloud.outbox_events"`
- **타입**: String (쉼표로 구분된 목록)
- **필수**: No (하지만 Outbox에서는 필수)
- **형식**: `{database}.{table}` 또는 정규식

#### 상세 설명

**정의**: Debezium이 캡처할 테이블 목록을 지정합니다. Outbox Pattern에서는 outbox_events 테이블만 캡처하도록 설정합니다.

**용도**:
- 특정 테이블만 CDC 대상으로 제한
- Outbox 전용 커넥터에서 불필요한 테이블 제외
- 성능 최적화 (binlog 파싱 부하 감소)

**예시**:
```json
// Outbox 테이블만
"table.include.list": "cloud.outbox_events"

// 여러 테이블 (CDC 용도)
"table.include.list": "cloud.users,cloud.orders,cloud.products"

// 정규식 사용
"table.include.list": "cloud\\.outbox_.*"
```

**설정값에 따른 동작**:

```json
// 시나리오 1: Outbox 전용
{
  "database.include.list": "cloud",
  "table.include.list": "cloud.outbox_events"
}
// 결과: outbox_events 테이블만 캡처
// 토픽: outbox.user, outbox.order, outbox.product
```

```json
// 시나리오 2: 잘못된 설정 (다른 테이블 포함)
{
  "database.include.list": "cloud",
  "table.include.list": "cloud.outbox_events,cloud.users"
}
// 결과: ❌ outbox_events는 EventRouter로 라우팅
//       ❌ users는 표준 CDC 토픽 생성 (혼란)
```

**주의사항**:
1. **정확한 테이블명 사용**: 오타 시 캡처 안 됨
2. **데이터베이스 prefix 필수**: `cloud.outbox_events` (O), `outbox_events` (X)
3. **대소문자 구분**: MariaDB는 Linux에서 대소문자 구분
4. **정규식 주의**: 백슬래시 이스케이프 필요 (`\\.`)

**확인 방법**:
```bash
# 커넥터 설정 확인
curl http://localhost:8083/connectors/mariadb-outbox-connector/config | jq '.["table.include.list"]'

# 캡처되는 테이블 확인 (로그)
docker logs kafka-connect-debezium 2>&1 | grep "Creating task"
```

### include.schema.changes

#### 기본 정보
- **값**: `"false"`
- **타입**: Boolean (문자열)
- **기본값**: `true`
- **필수**: No

#### 상세 설명

**정의**: DDL(Data Definition Language) 변경 이벤트를 Kafka 토픽으로 전송할지 여부를 결정합니다.

**용도**:
- 스키마 변경 이력 추적
- 다운스트림 시스템에 스키마 진화 전파
- 테이블 구조 변경 모니터링

**설정값에 따른 동작**:

##### `"true"` (기본값)
```json
"include.schema.changes": "true"
```

**동작**:
- DDL 이벤트를 `{topic.prefix}` 토픽으로 전송
- 예: `mariadb-outbox-source-server` 토픽에 DDL 이벤트 발행

**생성되는 이벤트**:
```sql
-- DDL 실행
ALTER TABLE outbox_events ADD COLUMN version INT;

-- Kafka 메시지 (토픽: mariadb-outbox-source-server)
{
  "source": {...},
  "databaseName": "cloud",
  "ddl": "ALTER TABLE outbox_events ADD COLUMN version INT",
  "tableChanges": [...]
}
```

##### `"false"` (Outbox 권장)
```json
"include.schema.changes": "false"
```

**동작**:
- DDL 이벤트를 Kafka로 전송하지 않음
- 스키마 히스토리는 내부 토픽에만 저장
- 비즈니스 이벤트만 토픽에 발행

**장점**:
- 불필요한 DDL 토픽 제거
- 토픽 관리 단순화
- Consumer 복잡도 감소

**Outbox Pattern 권장 이유**:

| 항목 | 이유 |
|------|------|
| 비즈니스 이벤트 중심 | Outbox는 INSERT 이벤트만 중요 |
| 스키마 변경 불필요 | DDL은 애플리케이션이 관리 |
| Consumer 단순화 | DDL 이벤트 처리 로직 불필요 |

**시나리오 비교**:

```json
// Outbox 커넥터 (권장)
{
  "include.schema.changes": "false",
  "table.include.list": "cloud.outbox_events"
}
// 생성 토픽: outbox.user, outbox.order, outbox.product
// DDL 토픽: 없음
```

```json
// CDC 커넥터 (DDL 필요 시)
{
  "include.schema.changes": "true",
  "table.include.list": "cloud.users,cloud.orders"
}
// 생성 토픽: mariadb-cdc.cloud.users, mariadb-cdc.cloud.orders
// DDL 토픽: mariadb-cdc (스키마 변경 이벤트 포함)
```

---

## 4. 스냅샷 설정

### snapshot.mode

#### 기본 정보
- **값**: `"initial"`
- **타입**: String (enum)
- **기본값**: `initial`
- **필수**: No

#### 상세 설명

**정의**: 커넥터 최초 실행 시 기존 테이블 데이터를 어떻게 처리할지 결정합니다.

**설정 옵션**:

| 값 | 동작 | 사용 시기 |
|---|------|----------|
| `initial` | 최초 1회 전체 스냅샷 수행 | 일반적인 경우 (권장) |
| `always` | 매번 재시작 시 스냅샷 수행 | 테스트 환경 |
| `never` | 스냅샷 수행 안 함 | 실시간만 필요 시 |
| `when_needed` | 오프셋 없을 때만 스냅샷 | 재시작 최적화 |
| `schema_only` | 스키마만 캡처, 데이터 제외 | 과거 데이터 불필요 |

#### 설정값에 따른 동작

##### `"initial"` (권장)
```json
"snapshot.mode": "initial"
```

**동작 순서**:
1. 커넥터 최초 실행 확인 (오프셋 없음)
2. 테이블 읽기 잠금 획득
3. 현재 binlog position 기록
4. 테이블 전체 스캔 및 Kafka 전송
5. 잠금 해제
6. binlog position부터 실시간 CDC 시작

**예시 (Outbox 테이블)**:
```sql
-- outbox_events 테이블에 5개 레코드 존재
SELECT COUNT(*) FROM outbox_events;
-- 결과: 5

-- 커넥터 시작 시
-- 1. 5개 레코드 모두 Kafka로 전송 (스냅샷)
-- 2. 이후 INSERT만 실시간 전송
```

**Kafka 토픽 결과**:
- `outbox.user`: 스냅샷 2개 + 실시간 이벤트
- `outbox.order`: 스냅샷 2개 + 실시간 이벤트
- `outbox.product`: 스냅샷 1개 + 실시간 이벤트

##### `"schema_only"` (과거 데이터 불필요 시)
```json
"snapshot.mode": "schema_only"
```

**동작**:
- 테이블 스키마만 캡처
- 기존 데이터는 무시
- 커넥터 시작 후 INSERT만 캡처

**사용 시나리오**:
- Outbox 테이블에 오래된 이벤트만 있음
- 과거 이벤트는 이미 처리됨
- 실시간 이벤트만 필요

**예시**:
```sql
-- 기존 100만 개 이벤트 (처리 완료)
SELECT COUNT(*) FROM outbox_events WHERE processed = 1;
-- 결과: 1,000,000

-- schema_only 모드로 커넥터 시작
-- → 기존 100만 개 무시
-- → 새로운 INSERT만 Kafka로 전송
```

##### `"never"` (주의 필요)
```json
"snapshot.mode": "never"
```

**동작**:
- 스냅샷 완전 건너뛰기
- binlog position만 기록
- 실시간 CDC만 동작

**위험**:
- 커넥터 시작 전 데이터 누락
- 초기 데이터 동기화 안 됨

**사용 시나리오**:
- 빈 테이블에서 시작
- 다른 방법으로 이미 동기화됨

##### `"always"` (테스트 전용)
```json
"snapshot.mode": "always"
```

**동작**:
- 매번 재시작 시 전체 스냅샷
- 오프셋 무시

**문제점**:
- 중복 이벤트 발생
- 성능 저하
- 프로덕션 사용 금지

#### Outbox Pattern 권장 설정

```json
{
  "snapshot.mode": "initial",
  "snapshot.locking.mode": "minimal"
}
```

**이유**:
1. 커넥터 재배포 시 이벤트 누락 방지
2. 최초 1회만 수행으로 성능 영향 최소화
3. 이후 재시작 시 오프셋부터 재개

### snapshot.locking.mode

#### 기본 정보
- **값**: `"minimal"`
- **타입**: String (enum)
- **기본값**: `minimal`
- **필수**: No

#### 상세 설명

**정의**: 스냅샷 수행 중 데이터베이스 테이블에 적용할 잠금 수준을 결정합니다.

**설정 옵션**:

| 값 | 잠금 범위 | 쓰기 블록 | 읽기 블록 | 사용 시기 |
|---|----------|----------|----------|----------|
| `minimal` | 짧은 시간 | 최소 | 없음 | 일반적 (권장) |
| `extended` | 스냅샷 전체 | 있음 | 없음 | 일관성 중요 |
| `none` | 없음 | 없음 | 없음 | 읽기 전용 복제본 |

#### 설정값에 따른 동작

##### `"minimal"` (권장)
```json
"snapshot.locking.mode": "minimal"
```

**동작**:
1. **짧은 글로벌 읽기 잠금**: binlog position 획득 시
2. **즉시 해제**: position 기록 후
3. **테이블 읽기**: 잠금 없이 진행

**타임라인**:
```
T0: FLUSH TABLES WITH READ LOCK    (모든 쓰기 차단)
T1: SHOW MASTER STATUS             (binlog position 획득)
T2: UNLOCK TABLES                   (잠금 해제 - 수 초 이내)
T3~Tn: SELECT * FROM outbox_events (쓰기 가능, 읽기 진행)
```

**영향**:
- 쓰기 차단 시간: 수 초 이내
- 애플리케이션 영향: 최소
- 일관성: 보장 (binlog position 기준)

**사용 시나리오**:
- 프로덕션 환경
- 고가용성 요구사항
- 쓰기 트래픽이 많은 시스템

##### `"extended"`
```json
"snapshot.locking.mode": "extended"
```

**동작**:
1. 글로벌 읽기 잠금 획득
2. 스냅샷 전체 기간 유지
3. 스냅샷 완료 후 해제

**타임라인**:
```
T0: FLUSH TABLES WITH READ LOCK    (모든 쓰기 차단)
T1~Tn: SELECT * FROM outbox_events (스냅샷 수행)
Tn+1: UNLOCK TABLES                 (잠금 해제 - 수 분)
```

**영향**:
- 쓰기 차단 시간: 스냅샷 전체 기간 (수 분~수 시간)
- 애플리케이션 영향: 큼
- 일관성: 완벽 보장

**사용 시나리오**:
- 야간 배치 작업
- 쓰기 트래픽 없는 시간대
- 절대 일관성 필요

##### `"none"` (특수 상황)
```json
"snapshot.locking.mode": "none"
```

**동작**:
- 잠금 없이 스냅샷 수행
- binlog position은 추정

**위험**:
- 일관성 보장 안 됨
- 트랜잭션 중간 상태 캡처 가능

**사용 시나리오**:
- 읽기 전용 복제본 사용
- 데이터 일관성이 중요하지 않음
- 쓰기 차단 절대 불가

#### 실제 영향 시나리오

##### 시나리오 1: 소규모 Outbox 테이블 (minimal)
```json
{
  "snapshot.mode": "initial",
  "snapshot.locking.mode": "minimal",
  "table.include.list": "cloud.outbox_events"
}
```

**outbox_events 테이블**: 1,000건
- 잠금 시간: 1초 이내
- 스냅샷 시간: 5초
- 애플리케이션 영향: 무시 가능

##### 시나리오 2: 대규모 테이블 (minimal)
```json
{
  "snapshot.mode": "initial",
  "snapshot.locking.mode": "minimal",
  "table.include.list": "cloud.large_outbox"
}
```

**large_outbox 테이블**: 1,000만 건
- 잠금 시간: 1초 이내
- 스냅샷 시간: 30분
- 애플리케이션 영향: 스냅샷 중 쓰기 가능 (minimal이므로)

##### 시나리오 3: 야간 배치 (extended)
```json
{
  "snapshot.mode": "always",
  "snapshot.locking.mode": "extended"
}
```

**운영 시간**: 야간 2:00 ~ 3:00
- 잠금 시간: 전체 스냅샷 시간 (1시간)
- 쓰기 차단: 1시간
- 애플리케이션 영향: 야간이므로 허용 가능

#### Outbox Pattern 최적 조합

```json
{
  "snapshot.mode": "initial",
  "snapshot.locking.mode": "minimal",
  "table.include.list": "cloud.outbox_events"
}
```

**이유**:
1. Outbox 테이블은 일반적으로 작음 (이벤트는 처리 후 삭제)
2. 쓰기 차단 시간 최소화 (수 초)
3. 프로덕션 환경에서 안전
4. 일관성 보장 (binlog position 기준)

**모니터링**:
```bash
# 스냅샷 진행 상황 확인
curl http://localhost:8083/connectors/mariadb-outbox-connector/status

# 로그 확인
docker logs kafka-connect-debezium 2>&1 | grep -i snapshot
```

---

## 5. 토픽 자동 생성 설정

### topic.creation.enable

#### 기본 정보
- **값**: `"true"`
- **타입**: Boolean (문자열)
- **기본값**: `false`
- **필수**: No

#### 상세 설명

**정의**: Kafka Connect가 자동으로 토픽을 생성할지 결정합니다.

**용도**:
- EventRouter가 생성하는 `outbox.*` 토픽 자동 생성
- 수동 토픽 생성 작업 제거
- 동적인 aggregate_type 대응

**설정값에 따른 동작**:

##### `"true"` (권장)
```json
{
  "topic.creation.enable": "true",
  "topic.creation.default.partitions": "3",
  "topic.creation.default.replication.factor": "1"
}
```

**동작**:
1. 새로운 aggregate_type 감지 (예: "Order")
2. 토픽 `outbox.Order` 존재 확인
3. 없으면 자동 생성 (파티션 3, 복제 1)
4. 메시지 전송

**장점**:
- 운영 편의성
- aggregate_type 추가 시 자동 대응
- 개발 환경 빠른 설정

##### `"false"` (기본값)
```json
"topic.creation.enable": "false"
```

**동작**:
- 토픽이 없으면 에러 발생
- 사전에 수동으로 토픽 생성 필요

**수동 토픽 생성**:
```bash
# 각 aggregate_type별로 토픽 생성
kafka-topics.sh --create \
  --bootstrap-server kafka:9092 \
  --topic outbox.Order \
  --partitions 3 \
  --replication-factor 3

kafka-topics.sh --create \
  --bootstrap-server kafka:9092 \
  --topic outbox.User \
  --partitions 3 \
  --replication-factor 3
```

**장점**:
- 명시적 토픽 관리
- 토픽별 상세 설정 가능
- 프로덕션 권장

**필요 조건**:
```properties
# Kafka broker 설정
auto.create.topics.enable=true
```

### topic.creation.default.partitions

#### 기본 정보
- **값**: `"3"`
- **타입**: Integer (문자열)
- **기본값**: Kafka broker 설정 따름
- **필수**: No

#### 상세 설명

**정의**: 자동 생성되는 토픽의 파티션 수입니다.

**용도**:
- 병렬 처리 수준 결정
- Consumer 확장성
- 처리량 조절

**파티션 수 선택 가이드**:

```json
// 낮은 트래픽
"topic.creation.default.partitions": "1"
// 단일 Consumer로 충분

// 중간 트래픽 (권장)
"topic.creation.default.partitions": "3"
// 3개 Consumer까지 확장 가능

// 높은 트래픽
"topic.creation.default.partitions": "6"
// 6개 Consumer까지 확장 가능
```

**파티셔닝 효과**:
```
outbox.Order 토픽 (3 파티션)

Key: "order-123" → hash % 3 = Partition 0
Key: "order-456" → hash % 3 = Partition 1
Key: "order-789" → hash % 3 = Partition 2
```

**주의사항**:
1. 파티션 수는 증가만 가능 (감소 불가)
2. 너무 많은 파티션은 브로커 부하 증가
3. Consumer 수는 파티션 수 이하 권장

### topic.creation.default.replication.factor

#### 기본 정보
- **값**: `"1"` (개발), `"3"` (프로덕션)
- **타입**: Integer (문자열)
- **기본값**: Kafka broker 설정 따름
- **필수**: No

#### 상세 설명

**정의**: 자동 생성되는 토픽의 복제 계수입니다.

**용도**:
- 데이터 내구성
- 고가용성
- 장애 복구

**환경별 권장 설정**:

```json
// 개발 환경 (단일 브로커)
{
  "topic.creation.default.replication.factor": "1"
}
// 복제 없음, 빠른 테스트

// 스테이징 환경
{
  "topic.creation.default.replication.factor": "2"
}
// 최소 복제

// 프로덕션 환경 (권장)
{
  "topic.creation.default.replication.factor": "3"
}
// 2개 브로커 장애까지 견딤
```

**복제 계수 효과**:
```
replication.factor = 3

Broker 1: Leader
Broker 2: Follower (복제본)
Broker 3: Follower (복제본)

Broker 1 장애 → Broker 2가 Leader 승격
Broker 2 장애 → Broker 3이 Leader 승격
```

**제약사항**:
- 복제 계수는 브로커 수 이하여야 함
- 3 브로커 클러스터 → 최대 replication.factor = 3

---

## 6. 에러 처리 및 DLQ

### errors.tolerance

#### 기본 정보
- **값**: `"all"` (Outbox 권장)
- **타입**: String (enum)
- **옵션**: `none`, `all`
- **기본값**: `none`

#### 상세 설명

**정의**: 에러 발생 시 커넥터의 처리 방식을 결정합니다.

**Outbox vs CDC 비교**:

```json
// Outbox (관대한 처리)
{
  "errors.tolerance": "all",
  "errors.deadletterqueue.topic.name": "outbox-connector-errors"
}
// 이유: 일부 이벤트 실패해도 나머지는 계속 처리

// CDC (엄격한 처리)
{
  "errors.tolerance": "none"
}
// 이유: 데이터 일관성 최우선
```

**설정값에 따른 동작**:

##### `"all"` (Outbox 권장)
```json
{
  "errors.tolerance": "all",
  "errors.log.enable": "true",
  "errors.deadletterqueue.topic.name": "outbox-connector-errors",
  "errors.deadletterqueue.topic.replication.factor": "1",
  "errors.deadletterqueue.context.headers.enable": "true"
}
```

**동작**:
- 에러 발생해도 커넥터 계속 실행
- 실패한 메시지만 DLQ로 전송
- 나머지 이벤트는 정상 처리

**사용 케이스**:
- 이벤트 발행 연속성이 중요한 경우
- 일부 이벤트 실패해도 나머지는 계속 처리
- DLQ에서 실패 원인 분석 후 재처리

**DLQ 토픽 구조**:
```
outbox-connector-errors
├─ Key: 원본 aggregate_id
├─ Value: 실패한 outbox_events 레코드
└─ Headers:
   ├─ __connect.errors.topic: mariadb-outbox-source-server.cloud.outbox_events
   ├─ __connect.errors.partition: 0
   ├─ __connect.errors.offset: 12345
   ├─ __connect.errors.connector.name: mariadb-outbox-connector
   ├─ __connect.errors.task.id: 0
   ├─ __connect.errors.stage: TRANSFORMATION
   └─ __connect.errors.exception.message: "Failed to parse JSON payload"
```

### errors.deadletterqueue.topic.replication.factor

#### 기본 정보
- **값**: `"1"` (개발), `"3"` (프로덕션)
- **타입**: Integer (문자열)
- **기본값**: Kafka broker 기본값
- **필수**: No

#### 상세 설명

**정의**: DLQ 토픽의 복제 계수입니다.

**용도**:
- 에러 메시지 내구성 보장
- DLQ 고가용성
- 실패 이벤트 손실 방지

**환경별 설정**:

```json
// 개발 환경
{
  "errors.deadletterqueue.topic.name": "outbox-connector-errors",
  "errors.deadletterqueue.topic.replication.factor": "1"
}

// 프로덕션 환경
{
  "errors.deadletterqueue.topic.name": "outbox-connector-errors",
  "errors.deadletterqueue.topic.replication.factor": "3"
}
```

**권장 설정**: 비즈니스 토픽과 동일한 복제 계수 사용

### errors.deadletterqueue.context.headers.enable

#### 기본 정보
- **값**: `"true"`
- **타입**: Boolean (문자열)
- **기본값**: `false`
- **필수**: No (하지만 강력 권장)

#### 상세 설명

**정의**: 에러 컨텍스트 정보를 Kafka 헤더에 포함할지 결정합니다.

**용도**:
- 에러 원인 추적
- 디버깅 정보 제공
- 재처리 자동화

**설정값에 따른 동작**:

##### `"true"` (권장)
```json
"errors.deadletterqueue.context.headers.enable": "true"
```

**포함되는 헤더 정보**:
```json
{
  "__connect.errors.topic": "mariadb-outbox-source-server.cloud.outbox_events",
  "__connect.errors.partition": "0",
  "__connect.errors.offset": "12345",
  "__connect.errors.connector.name": "mariadb-outbox-connector",
  "__connect.errors.task.id": "0",
  "__connect.errors.stage": "TRANSFORMATION",
  "__connect.errors.exception.class.name": "org.apache.kafka.connect.errors.DataException",
  "__connect.errors.exception.message": "Failed to parse JSON payload: Unexpected character...",
  "__connect.errors.exception.stacktrace": "org.apache.kafka.connect..."
}
```

**stage 값**:
- `TRANSFORMATION`: Transform 단계 에러 (EventRouter)
- `CONVERTER`: Converter 단계 에러 (JSON 파싱)
- `HEADER_CONVERTER`: 헤더 변환 에러

**활용 예시**:

```java
// DLQ Consumer
@KafkaListener(topics = "outbox-connector-errors")
public void handleDlqMessage(
    ConsumerRecord<String, String> record
) {
    // 에러 정보 추출
    String errorStage = new String(
        record.headers().lastHeader("__connect.errors.stage").value()
    );
    String errorMessage = new String(
        record.headers().lastHeader("__connect.errors.exception.message").value()
    );
    String originalOffset = new String(
        record.headers().lastHeader("__connect.errors.offset").value()
    );
    
    log.error("Failed at stage: {}, offset: {}, reason: {}",
        errorStage, originalOffset, errorMessage);
    
    // 에러 타입별 처리
    if (errorStage.equals("TRANSFORMATION")) {
        // Transform 에러 → 페이로드 수정 후 재발행
        fixPayloadAndRepublish(record.value());
    }
}
```

##### `"false"` (기본값)
```json
"errors.deadletterqueue.context.headers.enable": "false"
```

**결과**:
- 에러 컨텍스트 없음
- 원본 메시지만 DLQ에 저장
- 디버깅 어려움

**DLQ 모니터링 예시**:

```bash
# DLQ 메시지 확인
kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic outbox-connector-errors \
  --from-beginning \
  --property print.headers=true \
  --property print.key=true

# 출력
__connect.errors.stage:TRANSFORMATION,__connect.errors.exception.message:Failed to parse JSON	order-123	{"event_id":"evt-001",...}
```

---

## 참고 자료

- [Debezium MySQL Connector 공식 문서](https://debezium.io/documentation/reference/stable/connectors/mysql.html)
- [Outbox Event Router SMT](https://debezium.io/documentation/reference/stable/transformations/outbox-event-router.html)
- [공통 설정 필드](./connector-field-common.md)
- [스키마 히스토리 설정](./connector-field-schema.md)

---

**문서 버전**: 1.0  
**최종 업데이트**: 2025-11-16
