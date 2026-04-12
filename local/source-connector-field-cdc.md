# Debezium CDC Source Connector 설정 가이드

## 개요

### CDC Source Connector란?

**Change Data Capture (CDC) Source Connector**는 데이터베이스의 모든 변경사항(INSERT, UPDATE, DELETE)을 실시간으로 캡처하여 Kafka 토픽으로 전송하는 커넥터입니다. Outbox Pattern과 달리 특정 테이블의 모든 DML 작업을 추적합니다.

#### CDC와 Outbox의 차이점

| 항목 | CDC Source | Outbox Pattern |
|------|-----------|----------------|
| **목적** | 데이터 복제, 동기화 | 이벤트 발행 |
| **대상 테이블** | 여러 비즈니스 테이블 | 단일 outbox_events 테이블 |
| **작업 타입** | INSERT, UPDATE, DELETE | INSERT만 |
| **토픽 구조** | `{prefix}.{db}.{table}` | `outbox.{aggregate_type}` |
| **메시지 형식** | CDC envelope (before/after) | 비즈니스 이벤트 |
| **Transform** | ExtractNewRecordState (선택) | EventRouter (필수) |
| **사용 사례** | DB 미러링, 분석, 검색 인덱싱 | 마이크로서비스 이벤트 |

### CDC Source 동작 흐름

```
[MariaDB/MySQL]
   ↓
[Binlog 스트리밍]
   ↓
[Debezium Source Connector]
   ↓
[Kafka 토픽: {prefix}.{db}.{table}]
   ↓
[Consumer / Sink Connector]
   ↓
[Target System (PostgreSQL, Elasticsearch 등)]
```

### CDC 메시지 구조

**테이블 변경**:
```sql
-- users 테이블
UPDATE users SET status = 'active' WHERE id = 123;
```

**Kafka 메시지 (토픽: mariadb-cdc.cloud.users)**:
```json
{
  "before": {
    "id": 123,
    "name": "John Doe",
    "email": "john@example.com",
    "status": "inactive"
  },
  "after": {
    "id": 123,
    "name": "John Doe",
    "email": "john@example.com",
    "status": "active"
  },
  "source": {
    "version": "2.4.0.Final",
    "connector": "mysql",
    "name": "mariadb-cdc",
    "ts_ms": 1700121600000,
    "db": "cloud",
    "table": "users",
    "server_id": 184054,
    "file": "mysql-bin.000003",
    "pos": 1234
  },
  "op": "u",
  "ts_ms": 1700121600123
}
```

**op 필드**:
- `c`: CREATE (INSERT)
- `u`: UPDATE
- `d`: DELETE
- `r`: READ (스냅샷)

---

## CDC Source 전용 설정 필드

### table.include.list (CDC 멀티 테이블)

#### 기본 정보
- **값**: `"cloud.users,cloud.orders,cloud.products"`
- **타입**: String (쉼표 구분)
- **필수**: No (하지만 권장)

#### 상세 설명

**정의**: CDC로 캡처할 여러 비즈니스 테이블을 지정합니다.

**Outbox와의 차이**:
- **Outbox**: 단일 테이블 (`cloud.outbox_events`)
- **CDC**: 여러 테이블 (`cloud.users,cloud.orders,cloud.products`)

**예시**:
```json
// CDC Source (여러 테이블)
{
  "table.include.list": "cloud.users,cloud.orders,cloud.products"
}

// Outbox (단일 테이블)
{
  "table.include.list": "cloud.outbox_events"
}
```

**생성되는 토픽**:
```
mariadb-cdc.cloud.users
mariadb-cdc.cloud.orders
mariadb-cdc.cloud.products
```

**테이블 패턴 사용**:
```json
// 정규식으로 여러 테이블 매칭
"table.include.list": "cloud\\.user.*,cloud\\.order.*"

// 결과
mariadb-cdc.cloud.users
mariadb-cdc.cloud.user_profiles
mariadb-cdc.cloud.orders
mariadb-cdc.cloud.order_items
```

### key.converter / value.converter (CDC 스키마 포함)

#### 기본 정보
- **값**: `"org.apache.kafka.connect.json.JsonConverter"`
- **schemas.enable**: `"true"` (CDC는 true 권장)

#### 상세 설명

**정의**: CDC는 before/after 구조를 유지하기 위해 스키마를 포함하는 것이 일반적입니다.

**Outbox와의 차이**:

```json
// CDC Source (스키마 포함)
{
  "key.converter": "org.apache.kafka.connect.json.JsonConverter",
  "key.converter.schemas.enable": "true",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "true"
}

// Outbox (스키마 없음)
{
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
```

**스키마 포함 이유**:
1. **타입 정보 보존**: INT, VARCHAR, DECIMAL 등
2. **Sink Connector 호환**: JDBC Sink가 스키마 기반으로 DDL 생성
3. **변경 추적**: before/after 구조 유지

**Kafka 메시지 (schemas.enable=true)**:
```json
{
  "schema": {
    "type": "struct",
    "fields": [
      {"field": "id", "type": "int32"},
      {"field": "name", "type": "string"},
      {"field": "email", "type": "string"}
    ]
  },
  "payload": {
    "before": {...},
    "after": {...},
    "source": {...},
    "op": "u"
  }
}
```

### include.schema.changes (CDC는 선택)

#### 기본 정보
- **값**: `"false"` (일반적)
- **CDC 권장**: `false` (Outbox와 동일)

#### 상세 설명

**정의**: DDL 변경을 별도 토픽으로 전송할지 결정합니다.

**설정값에 따른 동작**:

```json
// false (권장)
{
  "include.schema.changes": "false"
}
// 결과: DDL 이벤트는 내부 schema.history 토픽에만 저장
// 비즈니스 토픽: mariadb-cdc.cloud.users, mariadb-cdc.cloud.orders

// true (특수 케이스)
{
  "include.schema.changes": "true"
}
// 결과: DDL 이벤트를 mariadb-cdc 토픽으로 전송
// 비즈니스 토픽: mariadb-cdc.cloud.users, mariadb-cdc.cloud.orders
// DDL 토픽: mariadb-cdc (스키마 변경 이벤트)
```

**DDL 토픽이 필요한 경우**:
- 다운스트림 시스템이 스키마 변경을 자동 반영해야 할 때
- 스키마 진화 이력을 별도로 추적해야 할 때

---

## CDC Transform 설정

### transforms (ExtractNewRecordState)

#### 기본 정보
- **타입**: `"io.debezium.transforms.ExtractNewRecordState"`
- **필수**: No (선택적)

#### 상세 설명

**정의**: CDC envelope(before/after/source)를 제거하고 `after` 필드만 추출하여 간결한 메시지로 변환합니다.

**Transform 없이 (기본 CDC)**:
```json
{
  "before": {"id": 123, "name": "John", "status": "inactive"},
  "after": {"id": 123, "name": "John", "status": "active"},
  "source": {...},
  "op": "u",
  "ts_ms": 1700121600123
}
```

**Transform 적용 후**:
```json
{
  "id": 123,
  "name": "John",
  "status": "active"
}
```

**설정 예시**:
```json
{
  "transforms": "unwrap",
  "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
  "transforms.unwrap.drop.tombstones": "false",
  "transforms.unwrap.delete.handling.mode": "rewrite"
}
```

**transform 옵션**:

##### `drop.tombstones`
- **기본값**: `true`
- **의미**: DELETE 시 생성되는 tombstone(null value) 메시지 제거 여부

```json
// drop.tombstones: false
// DELETE 시 두 개 메시지
1. {"id": 123, "name": "John", "__deleted": "true"}
2. null (tombstone, 로그 압축용)

// drop.tombstones: true
// DELETE 시 한 개 메시지
1. {"id": 123, "name": "John", "__deleted": "true"}
```

##### `delete.handling.mode`
- **옵션**: `drop`, `rewrite`, `none`
- **기본값**: `drop`

```json
// drop: DELETE 이벤트 제거
// rewrite: {"id": 123, "__deleted": "true"} 형태로 변환
// none: before 값 유지
```

**사용 시나리오**:

##### 시나리오 1: 간결한 메시지 (Transform 사용)
```json
{
  "transforms": "unwrap",
  "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
```

**장점**: Consumer가 이해하기 쉬운 구조  
**단점**: before 값 손실, op 정보 손실

##### 시나리오 2: 완전한 CDC (Transform 없음)
```json
// transforms 설정 없음
```

**장점**: 모든 변경 정보 보존  
**단점**: 복잡한 메시지 구조

---

## CDC Source 성능 튜닝

### max.batch.size

#### 기본 정보
- **값**: `"2048"`
- **타입**: Integer
- **기본값**: `2048`

#### 상세 설명

**정의**: 한 번에 처리할 binlog 이벤트의 최대 개수입니다.

**설정값에 따른 동작**:

```json
// 높은 처리량
"max.batch.size": "4096"
// 장점: 빠른 처리
// 단점: 메모리 사용 증가

// 낮은 지연 시간
"max.batch.size": "1024"
// 장점: 낮은 레이턴시
// 단점: 처리량 감소
```

**권장 설정**:
- **고속 동기화**: `4096` ~ `8192`
- **실시간 우선**: `1024` ~ `2048`

### max.queue.size

#### 기본 정보
- **값**: `"8192"`
- **타입**: Integer
- **기본값**: `8192`

#### 상세 설명

**정의**: 내부 큐의 최대 크기입니다. Binlog Reader와 Kafka Writer 사이의 버퍼 역할을 합니다.

**동작 원리**:
```
[Binlog Reader] → [Queue: 8192] → [Kafka Writer]
```

**설정 가이드**:
```json
// 대용량 트래픽
"max.queue.size": "16384"

// 일반적인 경우
"max.queue.size": "8192"

// 메모리 제한 환경
"max.queue.size": "4096"
```

### snapshot.locking.mode

#### 기본 정보
- **값**: `"minimal"`
- **타입**: String (enum)
- **옵션**: `minimal`, `extended`, `none`
- **기본값**: `minimal`

#### 상세 설명

**정의**: 스냅샷 중 테이블 잠금 방식입니다.

**CDC vs Outbox**:
- **Outbox**: 단일 테이블 → 잠금 영향 최소
- **CDC**: 여러 테이블 → 잠금 영향 고려 필요

**옵션 비교**:

##### `"minimal"` (권장)
```json
{
  "snapshot.mode": "initial",
  "snapshot.locking.mode": "minimal"
}
```

**동작**:
- 스냅샷 시작 시 짧은 잠금 (binlog 위치 기록)
- 테이블 읽기 중 잠금 없음
- 프로덕션 안전

##### `"extended"`
```json
"snapshot.locking.mode": "extended"
```

**동작**:
- 전체 스냅샷 기간 동안 잠금 유지
- DML 블로킹 발생
- 개발 환경 전용

##### `"none"`
```json
"snapshot.locking.mode": "none"
```

**동작**:
- 잠금 없음
- 일관성 보장 안 됨
- 읽기 전용 복제본 전용

### snapshot.fetch.size

#### 기본 정보
- **값**: `"10240"`
- **타입**: Integer
- **기본값**: `2000`

#### 상세 설명

**정의**: 스냅샷 시 한 번에 가져올 행의 수입니다.

**용도**:
- 스냅샷 속도 최적화
- 메모리 사용량 조절
- 네트워크 왕복 횟수 감소

**설정 예시**:

```json
// 빠른 스냅샷
{
  "snapshot.mode": "initial",
  "snapshot.fetch.size": "10240"
}
// 장점: 빠른 초기 동기화
// 단점: 메모리 사용 증가

// 메모리 제한 환경
{
  "snapshot.fetch.size": "1000"
}
// 장점: 낮은 메모리
// 단점: 느린 스냅샷
```

### poll.interval.ms

#### 기본 정보
- **값**: `"1000"`
- **타입**: Integer
- **기본값**: `1000` (1초)

#### 상세 설명

**정의**: Binlog를 폴링하는 간격(밀리초)입니다.

**설정값에 따른 동작**:

```json
// 실시간에 가까운 처리
"poll.interval.ms": "500"
// 결과: 0.5초마다 binlog 확인
// 장점: 낮은 지연 시간
// 단점: CPU 사용 증가

// 배치 지향
"poll.interval.ms": "5000"
// 결과: 5초마다 binlog 확인
// 장점: CPU 사용 감소
// 단점: 높은 지연 시간
```

---

## CDC Source 에러 처리

### errors.tolerance

#### 기본 정보
- **값**: `"none"` (CDC 권장)
- **타입**: String (enum)
- **옵션**: `none`, `all`

#### 상세 설명

**정의**: 에러 발생 시 처리 방식을 결정합니다.

**CDC와 Outbox 비교**:

```json
// CDC Source (엄격한 에러 처리)
{
  "errors.tolerance": "none"
}
// 이유: 데이터 손실 방지 중요
// 에러 시: 커넥터 중단 → 수동 해결 → 재시작

// Outbox (관대한 에러 처리)
{
  "errors.tolerance": "all",
  "errors.deadletterqueue.topic.name": "outbox-connector-errors"
}
// 이유: 이벤트 발행 연속성 중요
// 에러 시: DLQ로 전송 → 계속 실행
```

**설정값에 따른 동작**:

##### `"none"` (CDC 권장)
```json
"errors.tolerance": "none"
```

**동작**:
- 에러 발생 시 커넥터 즉시 FAILED 상태
- 모든 데이터 처리 중단
- 수동 개입 필요

**장점**:
- 데이터 무결성 보장
- 문제 즉시 인지

**단점**:
- 운영 부담 증가
- 일시적 오류에도 중단

**사용 케이스**:
- 금융 거래 데이터
- 규제 준수 데이터
- 데이터 손실 절대 불가

##### `"all"` (Outbox 패턴)
```json
{
  "errors.tolerance": "all",
  "errors.log.enable": "true",
  "errors.deadletterqueue.topic.name": "dlq-cdc-errors",
  "errors.deadletterqueue.topic.replication.factor": "3",
  "errors.deadletterqueue.context.headers.enable": "true"
}
```

**동작**:
- 에러 발생해도 계속 실행
- 실패한 메시지만 DLQ로 전송
- 나머지 메시지는 정상 처리

**장점**:
- 고가용성
- 연속적인 데이터 흐름

**단점**:
- 데이터 손실 가능성
- DLQ 모니터링 필요

### errors.log.enable / errors.log.include.messages

#### 기본 정보
- **errors.log.enable**: `"true"`
- **errors.log.include.messages**: `"true"`
- **타입**: Boolean (문자열)

#### 상세 설명

**정의**: 에러를 커넥터 로그에 기록할지 결정합니다.

**설정 조합**:

```json
// 상세 로깅 (권장)
{
  "errors.log.enable": "true",
  "errors.log.include.messages": "true"
}
// 결과: 에러 + 실패한 메시지 내용 모두 로그

// 에러만 로깅
{
  "errors.log.enable": "true",
  "errors.log.include.messages": "false"
}
// 결과: 에러 정보만 로그 (메시지 내용 제외)

// 로깅 없음
{
  "errors.log.enable": "false"
}
// 결과: 로그 없음 (DLQ만 사용)
```

**로그 예시**:

```
// errors.log.include.messages: true
ERROR WorkerSourceTask{id=mariadb-cdc-source-0} failed to parse record from cloud.users at offset {"file":"mysql-bin.000003","pos":5678}
Message: {"before":null,"after":{"id":123,"name":"John","invalid_field":...}}
Exception: org.apache.kafka.connect.errors.DataException: Failed to deserialize data

// errors.log.include.messages: false
ERROR WorkerSourceTask{id=mariadb-cdc-source-0} failed to parse record at offset {"file":"mysql-bin.000003","pos":5678}
Exception: org.apache.kafka.connect.errors.DataException: Failed to deserialize data
```

### errors.deadletterqueue.topic.replication.factor

#### 기본 정보
- **값**: `"1"` (개발), `"3"` (프로덕션)
- **타입**: Integer (문자열)
- **필수**: No

#### 상세 설명

**정의**: DLQ 토픽의 복제 계수입니다.

**CDC에서의 중요성**:
- CDC는 데이터 손실 민감
- DLQ에 저장된 메시지도 중요 데이터
- 높은 복제 계수 권장

**환경별 설정**:

```json
// 프로덕션 (권장)
{
  "errors.deadletterqueue.topic.name": "dlq-cdc-errors",
  "errors.deadletterqueue.topic.replication.factor": "3"
}

// 개발
{
  "errors.deadletterqueue.topic.name": "dlq-cdc-errors",
  "errors.deadletterqueue.topic.replication.factor": "1"
}
```

### errors.deadletterqueue.context.headers.enable

#### 기본 정보
- **값**: `"true"`
- **타입**: Boolean (문자열)
- **기본값**: `false`
- **필수**: No (하지만 강력 권장)

#### 상세 설명

**정의**: 에러 컨텍스트를 Kafka 헤더에 포함할지 결정합니다.

**포함 정보**:
```json
{
  "__connect.errors.topic": "mariadb-cdc.cloud.users",
  "__connect.errors.partition": "1",
  "__connect.errors.offset": "12345",
  "__connect.errors.connector.name": "mariadb-cdc-source",
  "__connect.errors.task.id": "0",
  "__connect.errors.stage": "VALUE_CONVERTER",
  "__connect.errors.exception.class.name": "org.apache.kafka.connect.errors.DataException",
  "__connect.errors.exception.message": "Failed to deserialize value"
}
```

**DLQ 재처리 예시**:

```java
@KafkaListener(topics = "dlq-cdc-errors")
public void handleCdcError(ConsumerRecord<byte[], byte[]> record) {
    // 원본 정보 추출
    String originalTopic = new String(
        record.headers().lastHeader("__connect.errors.topic").value()
    );
    String errorStage = new String(
        record.headers().lastHeader("__connect.errors.stage").value()
    );
    
    // 테이블 식별
    String table = originalTopic.split("\\.")[2];  // "users"
    
    log.error("CDC error for table: {}, stage: {}", table, errorStage);
    
    // 재처리 로직
    if (errorStage.equals("VALUE_CONVERTER")) {
        // 스키마 문제 → 수동 수정 후 재발행
    }
}
```

---

## CDC Source 실전 설정 예시

### 예시 1: 표준 CDC (Envelope 유지)

```json
{
  "name": "mariadb-cdc-source",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "tasks.max": "1",
    
    "database.hostname": "mariadb-cdc",
    "database.port": "3306",
    "database.user": "cdc_user",
    "database.password": "password",
    
    "database.server.id": "184054",
    "topic.prefix": "mariadb-cdc",
    
    "database.include.list": "cloud",
    "table.include.list": "cloud.users,cloud.orders,cloud.products",
    "include.schema.changes": "false",
    
    "snapshot.mode": "initial",
    "snapshot.locking.mode": "minimal",
    
    "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
    "schema.history.internal.kafka.topic": "mariadb.dbhistory.cdc",
    
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "true",
    
    "errors.tolerance": "none"
  }
}
```

**생성 토픽**:
- `mariadb-cdc.cloud.users`
- `mariadb-cdc.cloud.orders`
- `mariadb-cdc.cloud.products`

**메시지 형식**: CDC envelope (before/after/source)

### 예시 2: 간결한 CDC (ExtractNewRecordState)

```json
{
  "name": "mariadb-cdc-simple",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "tasks.max": "1",
    
    "database.hostname": "mariadb-cdc",
    "database.server.id": "184055",
    "topic.prefix": "mariadb-cdc-simple",
    
    "table.include.list": "cloud.users,cloud.orders",
    
    "transforms": "unwrap",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "false",
    "transforms.unwrap.delete.handling.mode": "rewrite",
    
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false"
  }
}
```

**메시지 형식**: 간결한 레코드 (after 값만)

### 예시 3: 고성능 CDC (배치 처리)

```json
{
  "name": "mariadb-cdc-highperf",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    
    "database.server.id": "184056",
    "table.include.list": "cloud.users,cloud.orders,cloud.products,cloud.payments",
    
    "max.batch.size": "8192",
    "max.queue.size": "16384",
    "poll.interval.ms": "2000",
    
    "snapshot.mode": "initial",
    "snapshot.fetch.size": "10240",
    
    "errors.tolerance": "none"
  }
}
```

**최적화**:
- 높은 배치 크기: 처리량 증가
- 큰 큐 크기: 버스트 트래픽 대응
- 긴 폴링 간격: CPU 사용 감소

---

## CDC Source vs Outbox Pattern

### 설정 비교표

| 설정 필드 | CDC Source | Outbox Pattern |
|-----------|-----------|----------------|
| **table.include.list** | 여러 테이블 | 단일 outbox 테이블 |
| **transforms** | ExtractNewRecordState (선택) | EventRouter (필수) |
| **key.converter.schemas.enable** | `true` | `false` |
| **value.converter.schemas.enable** | `true` | `false` |
| **errors.tolerance** | `none` | `all` |
| **토픽 구조** | `{prefix}.{db}.{table}` | `outbox.{aggregate_type}` |

### 사용 사례 비교

#### CDC Source 사용 시
- **목적**: 데이터 복제, 동기화
- **시나리오**:
  - MariaDB → PostgreSQL 실시간 동기화
  - 트랜잭션 DB → 분석 DB 복제
  - 검색 인덱스 실시간 업데이트

#### Outbox Pattern 사용 시
- **목적**: 이벤트 발행
- **시나리오**:
  - 마이크로서비스 간 이벤트 전파
  - 주문 생성 → 재고 차감 이벤트
  - 결제 완료 → 배송 시작 이벤트

---

## 참고 자료

- [Debezium MySQL Connector 공식 문서](https://debezium.io/documentation/reference/stable/connectors/mysql.html)
- [Debezium Transforms](https://debezium.io/documentation/reference/stable/transformations/index.html)
- [ExtractNewRecordState SMT](https://debezium.io/documentation/reference/stable/transformations/event-flattening.html)

---

**문서 버전**: 1.0  
**최종 업데이트**: 2025-11-16
