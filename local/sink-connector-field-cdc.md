# Kafka Sink Connector 설정 가이드 (JDBC Sink)

## 개요

### Sink Connector란?

**Sink Connector**는 Kafka 토픽의 데이터를 읽어서 외부 시스템(데이터베이스, 파일, 검색엔진 등)으로 전송하는 커넥터입니다. CDC Source Connector와 함께 사용하여 데이터베이스 간 실시간 동기화를 구현합니다.

#### 전체 데이터 흐름

```
[Source DB: MariaDB]
       ↓
[CDC Source Connector]
       ↓
[Kafka Topics]
  - mariadb-cdc.cloud.users
  - mariadb-cdc.cloud.orders
  - mariadb-cdc.cloud.products
       ↓
[JDBC Sink Connector]
       ↓
[Target DB: PostgreSQL]
  - cdc_users
  - cdc_orders
  - cdc_products
```

### Sink Connector 종류

| Connector | Target System | 사용 사례 |
|-----------|---------------|----------|
| JDBC Sink | PostgreSQL, MySQL, Oracle | DB 동기화, 복제 |
| Elasticsearch Sink | Elasticsearch | 검색 인덱싱 |
| MongoDB Sink | MongoDB | NoSQL 동기화 |
| S3 Sink | AWS S3 | 데이터 레이크 |
| HDFS Sink | Hadoop HDFS | 빅데이터 분석 |

### JDBC Sink Connector 특징

- **자동 테이블 생성**: `auto.create=true`
- **스키마 진화**: `auto.evolve=true`
- **Upsert 지원**: INSERT or UPDATE
- **DELETE 처리**: Tombstone 메시지 기반

---

## Sink Connector 핵심 설정

### connector.class

#### 기본 정보
- **값**: `"io.debezium.connector.jdbc.JdbcSinkConnector"`
- **타입**: String (클래스명)
- **필수**: Yes

#### 상세 설명

**정의**: Debezium JDBC Sink Connector 클래스입니다.

**다른 Sink Connector**:
```json
// Debezium JDBC Sink (권장)
"connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector"

// Confluent JDBC Sink (대안)
"connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector"

// Elasticsearch Sink
"connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector"

// MongoDB Sink
"connector.class": "com.mongodb.kafka.connect.MongoSinkConnector"
```

**Debezium vs Confluent JDBC Sink**:

| 기능 | Debezium | Confluent |
|------|----------|-----------|
| CDC 지원 | 최적화됨 | 일반적 |
| DELETE 처리 | Tombstone 지원 | 제한적 |
| 스키마 진화 | 고급 | 기본 |
| 라이센스 | Apache 2.0 | Confluent Community |

---

## 토픽 구독 설정

### topics vs topics.regex

#### 기본 정보
- **topics**: 명시적 토픽 리스트
- **topics.regex**: 정규식 패턴

#### 상세 설명

**정의**: Sink Connector가 구독할 Kafka 토픽을 지정합니다.

##### topics (명시적)
```json
"topics": "mariadb-cdc.cloud.users,mariadb-cdc.cloud.orders"
```

**장점**: 명확한 토픽 지정  
**단점**: 테이블 추가 시 설정 변경 필요

##### topics.regex (정규식, 권장)
```json
"topics.regex": "mariadb-cdc\\.cloud\\.(users|orders|products)"
```

**장점**: 동적 토픽 매칭, 확장성  
**단점**: 예상치 못한 토픽 구독 가능성

**정규식 패턴 예시**:
```json
// 모든 cloud 테이블
"topics.regex": "mariadb-cdc\\.cloud\\..*"

// 특정 테이블만
"topics.regex": "mariadb-cdc\\.cloud\\.(users|orders|products)"

// 환경별 구분
"topics.regex": "prod-mariadb-cdc\\.cloud\\..*"
```

**주의사항**:
- 백슬래시 이스케이프 필요: `\\.` (점 문자)
- OR 조건: `(users|orders)`
- 와일드카드: `.*`

---

## 데이터베이스 연결 설정

### connection.url

#### 기본 정보
- **값**: `"jdbc:postgresql://pgvector:5432/cloud"`
- **타입**: String (JDBC URL)
- **필수**: Yes

#### 상세 설명

**정의**: Target 데이터베이스의 JDBC 연결 URL입니다.

**데이터베이스별 URL 형식**:

##### PostgreSQL
```json
"connection.url": "jdbc:postgresql://pgvector:5432/cloud?tcpKeepAlive=true&socketTimeout=30"
```

**파라미터**:
- `tcpKeepAlive=true`: 연결 유지
- `socketTimeout=30`: 소켓 타임아웃 (초)
- `connectTimeout=30`: 연결 타임아웃 (초)

##### MySQL/MariaDB
```json
"connection.url": "jdbc:mysql://mysql:3306/target_db?useSSL=false&serverTimezone=UTC"
```

**파라미터**:
- `useSSL=false`: SSL 비활성화 (개발 환경)
- `serverTimezone=UTC`: 타임존 설정

##### Oracle
```json
"connection.url": "jdbc:oracle:thin:@//oracle-host:1521/ORCL"
```

##### SQL Server
```json
"connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=target_db"
```

### connection.username / connection.password

#### 기본 정보
- **username**: `"postgres"`
- **password**: `"postgres"`
- **필수**: Yes

#### 상세 설명

**정의**: Target 데이터베이스 접속 계정입니다.

**필요 권한**:
```sql
-- PostgreSQL
GRANT CREATE, INSERT, UPDATE, DELETE ON DATABASE cloud TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres;

-- MySQL
GRANT CREATE, INSERT, UPDATE, DELETE ON target_db.* TO 'sink_user'@'%';
FLUSH PRIVILEGES;
```

**보안 권장사항**:
```json
// 환경 변수 사용
{
  "connection.username": "${env:DB_USERNAME}",
  "connection.password": "${env:DB_PASSWORD}"
}

// Kubernetes Secret
{
  "connection.username": "${secret:db-credentials:username}",
  "connection.password": "${secret:db-credentials:password}"
}
```

---

## 테이블 생성 및 스키마 진화

### table.name.format

#### 기본 정보
- **값**: `"cdc_${source.table}"`
- **타입**: String (패턴)
- **필수**: No
- **기본값**: `${source.table}`

#### 상세 설명

**정의**: Target 데이터베이스에 생성될 테이블 이름의 패턴입니다.

**변수**:
- `${source.table}`: Source 테이블명
- `${topic}`: Kafka 토픽명

**패턴 예시**:

```json
// 접두사 추가
"table.name.format": "cdc_${source.table}"

// Source: users
// Target: cdc_users

// 접두사 + 접미사
"table.name.format": "sync_${source.table}_replica"

// Source: orders
// Target: sync_orders_replica

// 토픽 이름 사용
"table.name.format": "${topic}"

// 토픽: mariadb-cdc.cloud.users
// Target: mariadb-cdc.cloud.users (권장 안 함, 점 포함)
```

**실제 매핑**:

| Source 토픽 | source.table | table.name.format | Target 테이블 |
|-------------|--------------|-------------------|--------------|
| mariadb-cdc.cloud.users | users | `cdc_${source.table}` | cdc_users |
| mariadb-cdc.cloud.orders | orders | `sync_${source.table}` | sync_orders |
| mariadb-cdc.cloud.products | products | `${source.table}_copy` | products_copy |

### auto.create

#### 기본 정보
- **값**: `"true"`
- **타입**: Boolean (문자열)
- **기본값**: `false`
- **필수**: No

#### 상세 설명

**정의**: Target 테이블이 없을 때 자동으로 생성할지 결정합니다.

**설정값에 따른 동작**:

##### `"true"` (권장)
```json
"auto.create": "true"
```

**동작**:
1. Sink Connector 시작
2. Kafka 메시지의 스키마 분석
3. Target DB에 테이블 자동 생성
4. 데이터 INSERT 시작

**생성된 DDL 예시 (PostgreSQL)**:
```sql
CREATE TABLE cdc_users (
  id INTEGER PRIMARY KEY,
  name VARCHAR(255),
  email VARCHAR(255),
  status VARCHAR(50),
  created_at TIMESTAMP
);
```

**장점**:
- 초기 설정 간소화
- 수동 DDL 불필요
- 빠른 프로토타이핑

**단점**:
- 최적화되지 않은 스키마 (인덱스, 제약조건 없음)
- 프로덕션에서는 수동 DDL 권장

##### `"false"` (프로덕션)
```json
"auto.create": "false"
```

**동작**:
- 테이블이 없으면 에러 발생
- 사전에 수동으로 테이블 생성 필요

**프로덕션 DDL 예시**:
```sql
CREATE TABLE cdc_users (
  id INTEGER PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  status VARCHAR(50) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_email ON cdc_users(email);
CREATE INDEX idx_users_status ON cdc_users(status);
```

### auto.evolve

#### 기본 정보
- **값**: `"true"`
- **타입**: Boolean (문자열)
- **기본값**: `false`
- **필수**: No

#### 상세 설명

**정의**: Source 스키마 변경 시 Target 테이블을 자동으로 변경할지 결정합니다.

**스키마 진화 시나리오**:

```sql
-- Source (MariaDB): 컬럼 추가
ALTER TABLE users ADD COLUMN phone VARCHAR(20);

-- Kafka 메시지에 phone 필드 추가됨
```

**auto.evolve=true**:
```sql
-- Target (PostgreSQL): 자동으로 컬럼 추가
ALTER TABLE cdc_users ADD COLUMN phone VARCHAR(20);
```

**auto.evolve=false**:
```
ERROR: Column 'phone' does not exist in table 'cdc_users'
Connector status: FAILED
```

**지원되는 스키마 변경**:
- 컬럼 추가 (ADD COLUMN)
- 컬럼 타입 확장 (VARCHAR(50) → VARCHAR(100))

**지원되지 않는 변경**:
- 컬럼 삭제
- 컬럼 이름 변경
- 타입 축소 (VARCHAR(100) → VARCHAR(50))

### schema.evolution

#### 기본 정보
- **값**: `"basic"`
- **타입**: String (enum)
- **옵션**: `none`, `basic`, `advanced`
- **기본값**: `none`

#### 상세 설명

**정의**: 스키마 진화의 수준을 결정합니다.

**옵션 비교**:

| 옵션 | 컬럼 추가 | 타입 변경 | 제약조건 |
|------|-----------|----------|----------|
| `none` | ❌ | ❌ | ❌ |
| `basic` | ✅ | 제한적 | ❌ |
| `advanced` | ✅ | ✅ | ✅ |

**설정 예시**:
```json
// 기본 스키마 진화 (권장)
{
  "auto.create": "true",
  "auto.evolve": "true",
  "schema.evolution": "basic"
}

// 고급 스키마 진화 (주의 필요)
{
  "auto.evolve": "true",
  "schema.evolution": "advanced"
}

// 스키마 고정 (프로덕션)
{
  "auto.create": "false",
  "auto.evolve": "false",
  "schema.evolution": "none"
}
```

---

## INSERT/UPDATE/DELETE 처리

### insert.mode

#### 기본 정보
- **값**: `"upsert"`
- **타입**: String (enum)
- **옵션**: `insert`, `upsert`, `update`
- **기본값**: `insert`

#### 상세 설명

**정의**: 레코드 삽입 방식을 결정합니다.

##### `"insert"` (단순 삽입)
```json
"insert.mode": "insert"
```

**동작**: 항상 INSERT 실행

**문제점**:
```sql
-- 첫 번째 메시지 (INSERT)
INSERT INTO cdc_users VALUES (123, 'John', 'active');
-- 성공

-- 두 번째 메시지 (UPDATE)
INSERT INTO cdc_users VALUES (123, 'John', 'inactive');
-- 에러: Duplicate key
```

##### `"upsert"` (INSERT or UPDATE, 권장)
```json
"insert.mode": "upsert",
"primary.key.mode": "record_key"
```

**동작**: 
- 레코드가 없으면 INSERT
- 레코드가 있으면 UPDATE

**SQL 변환 (PostgreSQL)**:
```sql
INSERT INTO cdc_users (id, name, status)
VALUES (123, 'John', 'inactive')
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    status = EXCLUDED.status;
```

**SQL 변환 (MySQL)**:
```sql
INSERT INTO cdc_users (id, name, status)
VALUES (123, 'John', 'inactive')
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  status = VALUES(status);
```

##### `"update"` (UPDATE만)
```json
"insert.mode": "update"
```

**동작**: 항상 UPDATE 실행

**사용 케이스**: 기존 레코드만 업데이트 (INSERT 불필요)

### primary.key.mode

#### 기본 정보
- **값**: `"record_key"`
- **타입**: String (enum)
- **옵션**: `none`, `kafka`, `record_key`, `record_value`
- **기본값**: `none`

#### 상세 설명

**정의**: Primary Key를 결정하는 방식입니다.

##### `"record_key"` (Kafka Key 사용, 권장)
```json
"primary.key.mode": "record_key"
```

**동작**: Kafka 메시지의 Key를 Primary Key로 사용

**Kafka 메시지**:
```json
{
  "key": {
    "schema": {
      "fields": [{"field": "id", "type": "int32"}]
    },
    "payload": {"id": 123}
  },
  "value": {
    "payload": {
      "after": {"id": 123, "name": "John", "status": "active"}
    }
  }
}
```

**Target 테이블**:
```sql
-- id=123이 Primary Key
INSERT INTO cdc_users (id, name, status)
VALUES (123, 'John', 'active')
ON CONFLICT (id) DO UPDATE ...
```

##### `"record_value"` (Value 필드 사용)
```json
{
  "primary.key.mode": "record_value",
  "primary.key.fields": "id"
}
```

**동작**: Value의 특정 필드를 Primary Key로 사용

##### `"kafka"` (Kafka 메타데이터 사용)
```json
"primary.key.mode": "kafka"
```

**동작**: `(topic, partition, offset)` 조합을 Primary Key로 사용

**사용 케이스**: Primary Key가 없는 테이블

### delete.enabled

#### 기본 정보
- **값**: `"true"`
- **타입**: Boolean (문자열)
- **기본값**: `false`
- **필수**: No

#### 상세 설명

**정의**: DELETE 이벤트 처리 여부를 결정합니다.

**CDC DELETE 흐름**:

```sql
-- Source (MariaDB)
DELETE FROM users WHERE id = 123;
```

**Kafka 메시지 (두 개)**:
```json
// 1. DELETE 이벤트
{
  "key": {"id": 123},
  "value": {
    "before": {"id": 123, "name": "John"},
    "after": null,
    "op": "d"
  }
}

// 2. Tombstone (로그 압축용)
{
  "key": {"id": 123},
  "value": null
}
```

**delete.enabled=true**:
```sql
-- Target (PostgreSQL)
DELETE FROM cdc_users WHERE id = 123;
```

**delete.enabled=false**:
- DELETE 이벤트 무시
- Tombstone도 무시
- 데이터 유지

**사용 시나리오**:

##### 시나리오 1: 완전 동기화 (true)
```json
{
  "insert.mode": "upsert",
  "delete.enabled": "true"
}
```

**결과**: Source와 Target이 완벽히 일치

##### 시나리오 2: Soft Delete (false)
```json
{
  "insert.mode": "upsert",
  "delete.enabled": "false"
}
```

**결과**: DELETE 발생해도 Target 데이터 유지

**대안: Soft Delete 구현**:
```sql
-- Source에서 Soft Delete
UPDATE users SET deleted_at = NOW() WHERE id = 123;

-- Target에도 Soft Delete 반영 (UPDATE로 처리)
```

---

## 성능 최적화

### batch.size

#### 기본 정보
- **값**: `"100"`
- **타입**: Integer
- **기본값**: `3000`

#### 상세 설명

**정의**: 한 번에 처리할 레코드의 최대 개수입니다.

**설정값에 따른 동작**:

```json
// 낮은 지연 시간
"batch.size": "100"
// 결과: 100개마다 INSERT/UPDATE 실행
// 장점: 실시간에 가까움
// 단점: DB 부하 증가

// 높은 처리량
"batch.size": "5000"
// 결과: 5000개 모아서 한 번에 처리
// 장점: DB 성능 최적화
// 단점: 지연 시간 증가
```

**권장 설정**:
- **실시간 동기화**: `100` ~ `500`
- **배치 동기화**: `3000` ~ `10000`

---

## 연결 풀 설정 (Hibernate C3P0)

### hibernate.c3p0.* 설정

#### 기본 정보
Debezium JDBC Sink는 Hibernate를 사용하며, C3P0 연결 풀을 지원합니다.

#### 주요 설정

```json
{
  "hibernate.connection.provider_class": "org.hibernate.connection.C3P0ConnectionProvider",
  "hibernate.c3p0.min_size": "1",
  "hibernate.c3p0.max_size": "5",
  "hibernate.c3p0.acquire_increment": "1",
  "hibernate.c3p0.timeout": "1800",
  "hibernate.c3p0.max_statements": "50",
  "hibernate.c3p0.idle_test_period": "30",
  "hibernate.c3p0.maxIdleTime": "300",
  "hibernate.c3p0.testConnectionOnCheckout": "true",
  "hibernate.c3p0.preferredTestQuery": "SELECT 1"
}
```

#### 상세 설명

##### `min_size` / `max_size`
- **min_size**: 최소 연결 수 (항상 유지)
- **max_size**: 최대 연결 수

```json
// 낮은 트래픽
{
  "hibernate.c3p0.min_size": "1",
  "hibernate.c3p0.max_size": "3"
}

// 높은 트래픽
{
  "hibernate.c3p0.min_size": "5",
  "hibernate.c3p0.max_size": "20"
}
```

##### `idle_test_period` / `maxIdleTime`
- **idle_test_period**: 유휴 연결 테스트 주기 (초)
- **maxIdleTime**: 유휴 연결 유지 시간 (초)

```json
{
  "hibernate.c3p0.idle_test_period": "30",  // 30초마다 테스트
  "hibernate.c3p0.maxIdleTime": "300"       // 5분 후 연결 종료
}
```

**동작**:
- 30초마다 유휴 연결에 `SELECT 1` 실행
- 응답 없으면 연결 제거
- 300초(5분) 동안 사용 안 되면 자동 종료

##### `testConnectionOnCheckout` / `preferredTestQuery`
- **testConnectionOnCheckout**: 연결 사용 전 테스트
- **preferredTestQuery**: 테스트 쿼리

```json
{
  "hibernate.c3p0.testConnectionOnCheckout": "true",
  "hibernate.c3p0.preferredTestQuery": "SELECT 1"
}
```

**동작**: 연결 풀에서 연결을 가져올 때 `SELECT 1` 실행하여 유효성 검증

---

## 에러 처리

### errors.tolerance (Sink는 all 가능)

#### 기본 정보
- **값**: `"all"` (Sink 권장)
- **타입**: String (enum)
- **옵션**: `none`, `all`

#### 상세 설명

**정의**: Sink Connector의 에러 처리 방식입니다.

**Source vs Sink**:

```json
// Source Connector (엄격)
{
  "errors.tolerance": "none"
}
// 이유: 데이터 손실 방지

// Sink Connector (관대)
{
  "errors.tolerance": "all",
  "errors.deadletterqueue.topic.name": "dlq-sink-errors"
}
// 이유: 일부 레코드 실패해도 나머지 처리 계속
```

**errors.tolerance=all 장점**:
- 네트워크 일시 장애 대응
- 스키마 불일치 레코드만 DLQ로 전송
- 연속적인 동기화 유지

### errors.retry.delay.max.ms / errors.retry.timeout

#### 기본 정보
- **delay.max.ms**: `"60000"` (60초)
- **timeout**: `"300000"` (5분)
- **타입**: Integer (문자열)

#### 상세 설명

**정의**: 재시도 정책을 설정합니다.

**재시도 메커니즘**:

```json
{
  "errors.tolerance": "all",
  "errors.retry.delay.max.ms": "60000",
  "errors.retry.timeout": "300000"
}
```

**동작 흐름**:
```
1. INSERT 실패 (예: DB 연결 끊김)
   ↓
2. 대기 1초 → 재시도
   ↓ 실패
3. 대기 2초 → 재시도
   ↓ 실패
4. 대기 4초 → 재시도
   ↓ 실패
5. 대기 8초 → 재시도
   ↓ 실패
...
N. 대기 60초 → 재시도 (최대 간격)
   ↓ 실패
총 경과 시간 300초 (5분)
   ↓
DLQ로 전송
```

**Exponential Backoff**:
- 초기 지연: 1초
- 지연 배수: 2배씩 증가
- 최대 지연: `errors.retry.delay.max.ms` (60초)
- 최대 시도 시간: `errors.retry.timeout` (300초)

**설정값에 따른 동작**:

##### 빠른 재시도 (네트워크 일시 장애)
```json
{
  "errors.retry.delay.max.ms": "10000",   // 10초
  "errors.retry.timeout": "60000"         // 1분
}
```

**재시도 패턴**:
```
1초 → 2초 → 4초 → 8초 → 10초 → 10초 → 10초 → ...
(총 1분 내 약 10회 재시도)
```

**사용 케이스**: 일시적 네트워크 끊김, Connection Pool 고갈

##### 긴 재시도 (DB 재시작 대기)
```json
{
  "errors.retry.delay.max.ms": "120000",  // 2분
  "errors.retry.timeout": "600000"        // 10분
}
```

**재시도 패턴**:
```
1초 → 2초 → 4초 → 8초 → 16초 → 32초 → 64초 → 120초 → 120초 → ...
(총 10분 내 재시도)
```

**사용 케이스**: DB 유지보수, 계획된 재시작

##### 재시도 없음 (즉시 DLQ)
```json
{
  "errors.retry.timeout": "0"
}
```

**동작**: 즉시 DLQ로 전송, 재시도 없음

**실제 시나리오**:

##### 시나리오 1: DB 일시 장애
```json
{
  "errors.tolerance": "all",
  "errors.retry.delay.max.ms": "30000",
  "errors.retry.timeout": "180000"
}
```

**상황**:
```
T0: PostgreSQL 연결 끊김
T1: 1초 후 재시도 → 실패
T3: 2초 후 재시도 → 실패
T7: 4초 후 재시도 → 실패
T15: 8초 후 재시도 → 실패
T31: 16초 후 재시도 → 실패
T61: 30초 후 재시도 → 성공 (DB 복구됨)
```

**결과**: 데이터 손실 없이 자동 복구

##### 시나리오 2: 재시도 시간 초과
```json
{
  "errors.tolerance": "all",
  "errors.retry.timeout": "60000",
  "errors.deadletterqueue.topic.name": "dlq-postgresql-sink"
}
```

**상황**:
```
T0: PostgreSQL 장애
... 60초 동안 계속 재시도 ...
T60: 여전히 실패
```

**결과**: DLQ에 저장, 수동 재처리 필요

### errors.log.enable / errors.log.include.messages

#### 기본 정보
- **errors.log.enable**: `"true"`
- **errors.log.include.messages**: `"true"`
- **타입**: Boolean (문자열)

#### 상세 설명

**정의**: Sink 에러를 커넥터 로그에 기록합니다.

**설정 조합**:

```json
// 상세 로깅 (권장)
{
  "errors.log.enable": "true",
  "errors.log.include.messages": "true"
}
```

**로그 예시**:
```
ERROR WorkerSinkTask{id=postgresql-sink-0} failed to execute INSERT for record from mariadb-cdc.cloud.users
Record: {"id":123,"name":"John","email":"invalid-email"}
Exception: org.postgresql.util.PSQLException: ERROR: duplicate key value violates unique constraint "users_pkey"
  Detail: Key (id)=(123) already exists.
```

**활용**:
- 에러 원인 즉시 파악
- 데이터 문제 진단
- 재처리 전략 수립

### errors.deadletterqueue.topic.replication.factor

#### 기본 정보
- **값**: `"1"` (개발), `"3"` (프로덕션)
- **타입**: Integer (문자열)

#### 상세 설명

**정의**: DLQ 토픽의 복제 계수입니다.

**Sink에서의 중요성**:
- 실패한 레코드 손실 방지
- 재처리 데이터 보존
- 고가용성

**설정 예시**:

```json
// 프로덕션
{
  "errors.deadletterqueue.topic.name": "dlq-postgresql-sink",
  "errors.deadletterqueue.topic.replication.factor": "3"
}

// 개발
{
  "errors.deadletterqueue.topic.name": "dlq-postgresql-sink",
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

**정의**: 에러 컨텍스트를 Kafka 헤더에 포함합니다.

**포함 정보**:
```json
{
  "__connect.errors.topic": "mariadb-cdc.cloud.users",
  "__connect.errors.partition": "1",
  "__connect.errors.offset": "12345",
  "__connect.errors.connector.name": "postgresql-sink-cdc",
  "__connect.errors.task.id": "0",
  "__connect.errors.stage": "TASK_PUT",
  "__connect.errors.exception.class.name": "org.postgresql.util.PSQLException",
  "__connect.errors.exception.message": "ERROR: duplicate key value violates unique constraint"
}
```

**stage 값 (Sink)**:
- `VALUE_CONVERTER`: Value 역직렬화 실패
- `TRANSFORMATION`: Transform 실패
- `TASK_PUT`: DB INSERT/UPDATE 실패

**DLQ 재처리 예시**:

```java
@KafkaListener(topics = "dlq-postgresql-sink")
public void handleSinkError(ConsumerRecord<byte[], byte[]> record) {
    // 에러 정보 추출
    String errorStage = new String(
        record.headers().lastHeader("__connect.errors.stage").value()
    );
    String errorMessage = new String(
        record.headers().lastHeader("__connect.errors.exception.message").value()
    );
    
    // 에러 타입별 처리
    if (errorMessage.contains("duplicate key")) {
        // 중복 키 에러 → UPDATE로 변경하여 재시도
        log.warn("Duplicate key detected, converting to UPDATE");
        updateExistingRecord(record.value());
        
    } else if (errorMessage.contains("foreign key constraint")) {
        // 외래키 에러 → 참조 데이터 먼저 삽입
        log.warn("Foreign key violation, inserting referenced record first");
        insertReferencedRecordFirst(record.value());
        
    } else if (errorStage.equals("TASK_PUT")) {
        // DB 에러 → 수동 검토 필요
        log.error("Database error: {}", errorMessage);
        alertOperations(record.value(), errorMessage);
    }
}
```

**DLQ 모니터링**:

```bash
# DLQ 메시지 수 확인
kafka-run-class.sh kafka.tools.GetOffsetShell \
  --broker-list kafka:9092 \
  --topic dlq-postgresql-sink

# DLQ 메시지 상세 확인
kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic dlq-postgresql-sink \
  --from-beginning \
  --property print.headers=true \
  --max-messages 10
```

---

## 실전 설정 예시

### 예시 1: 표준 CDC Sink (PostgreSQL)

```json
{
  "name": "postgresql-sink-cdc",
  "config": {
    "connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector",
    "tasks.max": "1",
    
    "topics.regex": "mariadb-cdc\\.cloud\\.(users|orders|products)",
    
    "connection.url": "jdbc:postgresql://pgvector:5432/cloud",
    "connection.username": "postgres",
    "connection.password": "postgres",
    
    "table.name.format": "cdc_${source.table}",
    "auto.create": "true",
    "auto.evolve": "true",
    "schema.evolution": "basic",
    
    "insert.mode": "upsert",
    "primary.key.mode": "record_key",
    "delete.enabled": "true",
    
    "batch.size": "100",
    
    "hibernate.c3p0.min_size": "1",
    "hibernate.c3p0.max_size": "5",
    
    "errors.tolerance": "all",
    "errors.deadletterqueue.topic.name": "dlq-postgresql-sink",
    
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "true"
  }
}
```

### 예시 2: 고성능 Sink (배치 처리)

```json
{
  "name": "postgresql-sink-highperf",
  "config": {
    "connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector",
    
    "topics.regex": "mariadb-cdc\\.cloud\\..*",
    
    "connection.url": "jdbc:postgresql://pgvector:5432/cloud",
    
    "auto.create": "false",
    "auto.evolve": "false",
    
    "insert.mode": "upsert",
    "primary.key.mode": "record_key",
    "delete.enabled": "true",
    
    "batch.size": "5000",
    
    "hibernate.c3p0.min_size": "10",
    "hibernate.c3p0.max_size": "50",
    "hibernate.c3p0.acquire_increment": "5",
    
    "errors.tolerance": "all"
  }
}
```

### 예시 3: Soft Delete Sink

```json
{
  "name": "postgresql-sink-softdelete",
  "config": {
    "connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector",
    
    "topics.regex": "mariadb-cdc\\.cloud\\.users",
    
    "connection.url": "jdbc:postgresql://pgvector:5432/cloud",
    
    "table.name.format": "users_replica",
    "auto.create": "true",
    "auto.evolve": "true",
    
    "insert.mode": "upsert",
    "primary.key.mode": "record_key",
    "delete.enabled": "false",
    
    "batch.size": "100"
  }
}
```

**Source Soft Delete**:
```sql
-- MariaDB
UPDATE users SET deleted_at = NOW() WHERE id = 123;

-- CDC 메시지: UPDATE 이벤트 (op=u)
-- PostgreSQL: UPDATE 반영 (DELETE 아님)
```

---

## Source + Sink 전체 설정 비교

### MariaDB → Kafka → PostgreSQL

```json
// Source Connector
{
  "name": "mariadb-cdc-source",
  "connector.class": "io.debezium.connector.mysql.MySqlConnector",
  "database.server.id": "184054",
  "topic.prefix": "mariadb-cdc",
  "table.include.list": "cloud.users,cloud.orders",
  "key.converter.schemas.enable": "true",
  "value.converter.schemas.enable": "true"
}

// Sink Connector
{
  "name": "postgresql-cdc-sink",
  "connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector",
  "topics.regex": "mariadb-cdc\\.cloud\\.(users|orders)",
  "connection.url": "jdbc:postgresql://pgvector:5432/cloud",
  "table.name.format": "cdc_${source.table}",
  "insert.mode": "upsert",
  "delete.enabled": "true",
  "key.converter.schemas.enable": "true",
  "value.converter.schemas.enable": "true"
}
```

**데이터 흐름**:
```
[MariaDB: users, orders]
       ↓
[Source Connector]
       ↓
[Kafka: mariadb-cdc.cloud.users, mariadb-cdc.cloud.orders]
       ↓
[Sink Connector]
       ↓
[PostgreSQL: cdc_users, cdc_orders]
```

---

## 참고 자료

- [Debezium JDBC Sink Connector 공식 문서](https://debezium.io/documentation/reference/stable/connectors/jdbc.html)
- [Kafka Connect JDBC Sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/index.html)
- [Hibernate C3P0 설정](https://www.mchange.com/projects/c3p0/)

---

**문서 버전**: 1.0  
**최종 업데이트**: 2025-11-16
