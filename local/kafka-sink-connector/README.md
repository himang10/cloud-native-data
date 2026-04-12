# PostgreSQL Sink Connector for CDC

이 디렉토리는 Kafka CDC 이벤트를 PostgreSQL(pgvector)로 전송하는 Sink Connector를 관리합니다.

## 📋 파일 구조

```
kafka-sink-connector/
├── README.md                           # 이 파일
├── postgresql-sink-connector.json      # PostgreSQL Sink 커넥터 설정
├── register-connector.sh               # 커넥터 등록
├── list-connectors.sh                  # 모든 커넥터 조회
├── check-connector.sh                  # 특정 커넥터 상세 정보
├── delete-connector.sh                 # 커넥터 삭제
└── check-postgresql-tables.sh          # PostgreSQL CDC 테이블 확인

../test-cdc-pipeline.sh                 # 전체 CDC 파이프라인 테스트 (상위 디렉토리)
```

## 🏗️ 아키텍처

```
MariaDB (Source)
    ↓ (CDC via Debezium)
Kafka Topics (mariadb-cdc.cloud.*)
    ↓ (Sink Connector)
PostgreSQL (pgvector)
```

## 🚀 빠른 시작

### 1. 사전 요구사항

다음 컨테이너가 실행 중이어야 합니다:

```bash
# 컨테이너 상태 확인
docker ps

# 필요한 컨테이너:
# - kafka (bitnamilegacy/kafka:4.0.0)
# - kafka-connect-debezium (Debezium 3.2.3)
# - mariadb-cdc (bitnamilegacy/mariadb:11.4.6)
# - pgvector (pgvector/pgvector:pg16)
```

그리고 MariaDB Source Connector가 이미 등록되어 있어야 합니다:

```bash
# Source Connector 확인
curl http://localhost:8083/connectors | jq
```

### 2. PostgreSQL Sink Connector 등록

```bash
./register-connector.sh postgresql-sink-connector.json
```

등록이 성공하면 다음과 같은 메시지가 표시됩니다:
```
✅ 성공: 커넥터 'postgresql-sink-cdc-connector'이(가) 등록되었습니다.
```

### 3. 커넥터 상태 확인

```bash
./check-connector.sh postgresql-sink-cdc-connector
```

출력 예시:
```json
{
  "name": "postgresql-sink-cdc-connector",
  "connector": {
    "state": "RUNNING",
    "worker_id": "localhost:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "localhost:8083"
    }
  ]
}
```

### 4. PostgreSQL 테이블 확인

CDC 이벤트가 PostgreSQL에 제대로 전송되었는지 확인합니다:

```bash
./check-postgresql-tables.sh
```

생성되는 테이블:
- `cdc_users`
- `cdc_products`
- `cdc_orders`

### 5. 전체 파이프라인 테스트

MariaDB → Kafka → PostgreSQL 전체 흐름을 테스트합니다:

```bash
cd ..
./test-cdc-pipeline.sh
```

## 📚 커넥터 설정 상세

### postgresql-sink-connector.json

```json
{
  "name": "postgresql-sink-cdc-connector",
  "config": {
    "connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector",
    "topics.regex": "mariadb-cdc\\.cloud\\.(users|orders|products)",
    "connection.url": "jdbc:postgresql://pgvector:5432/cloud",
    "table.name.format": "cdc_${source.table}",
    "auto.create": "true",
    "insert.mode": "upsert"
  }
}
```

주요 설정:
- **connector.class**: Debezium JDBC Sink 커넥터
- **topics.regex**: 구독할 Kafka 토픽 패턴
- **connection.url**: PostgreSQL 연결 URL (Docker 네트워크 내부 주소)
- **table.name.format**: 대상 테이블 이름 형식 (`cdc_users`, `cdc_products`, `cdc_orders`)
- **auto.create**: 테이블 자동 생성
- **insert.mode**: upsert (INSERT 또는 UPDATE)

## 🛠️ 스크립트 사용법

### register-connector.sh

PostgreSQL Sink Connector를 등록합니다.

```bash
./register-connector.sh postgresql-sink-connector.json
```

### list-connectors.sh

등록된 모든 커넥터(Source + Sink)를 조회합니다.

```bash
./list-connectors.sh
```

### check-connector.sh

특정 커넥터의 상세 정보를 확인합니다.

```bash
./check-connector.sh postgresql-sink-cdc-connector
```

### delete-connector.sh

커넥터를 삭제합니다.

```bash
./delete-connector.sh postgresql-sink-cdc-connector
```

### check-postgresql-tables.sh

PostgreSQL에 생성된 CDC 테이블과 데이터를 확인합니다.

```bash
./check-postgresql-tables.sh
```

출력:
- CDC 테이블 목록
- 각 테이블의 레코드 수
- 샘플 데이터 (최근 5건)

### test-cdc-pipeline.sh

전체 CDC 파이프라인을 테스트합니다.

```bash
./test-cdc-pipeline.sh
```

테스트 과정:
1. MariaDB에 새 사용자 추가
2. CDC 처리 대기
3. Kafka 토픽의 최신 메시지 확인
4. PostgreSQL의 cdc_users 테이블 확인

> 💡 **참고**: `test-cdc-pipeline.sh`는 전체 CDC 파이프라인을 테스트하는 통합 스크립트로,
> source와 sink 모두를 확인하므로 상위 디렉토리(`/local/`)에 위치합니다.

## 🧪 수동 테스트

### 1. MariaDB에 데이터 추가

```bash
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud -e \
  "INSERT INTO users (username, email, full_name) VALUES ('new_user', 'new@example.com', 'New User');"
```

### 2. Kafka 토픽 확인

```bash
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic mariadb-cdc.cloud.users \
  --from-beginning \
  --max-messages 1
```

### 3. PostgreSQL 확인

```bash
docker exec pgvector psql -U postgres -d cloud -c "SELECT * FROM cdc_users ORDER BY id DESC LIMIT 5;"
```

### 4. 데이터 업데이트 테스트

```bash
# MariaDB 업데이트
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud -e \
  "UPDATE users SET full_name='Updated Name' WHERE username='new_user';"

# 잠시 대기
sleep 3

# PostgreSQL 확인
docker exec pgvector psql -U postgres -d cloud -c \
  "SELECT * FROM cdc_users WHERE username='new_user';"
```

### 5. 데이터 삭제 테스트

```bash
# MariaDB 삭제
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud -e \
  "DELETE FROM users WHERE username='new_user';"

# PostgreSQL 확인 (delete.enabled=true이므로 PostgreSQL에서도 삭제됨)
docker exec pgvector psql -U postgres -d cloud -c \
  "SELECT * FROM cdc_users WHERE username='new_user';"
```

## 🔍 문제 해결

### 커넥터가 FAILED 상태인 경우

```bash
# 상세 에러 확인
./check-connector.sh postgresql-sink-cdc-connector

# Kafka Connect 로그 확인
docker logs kafka-connect-debezium -f

# 커넥터 재시작
curl -X POST http://localhost:8083/connectors/postgresql-sink-cdc-connector/restart
```

### 테이블이 생성되지 않는 경우

1. Source Connector가 정상 동작하는지 확인:
```bash
curl http://localhost:8083/connectors/mariadb-source-cdc-connector/status | jq
```

2. Kafka 토픽에 메시지가 있는지 확인:
```bash
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic mariadb-cdc.cloud.users \
  --from-beginning \
  --max-messages 1
```

3. PostgreSQL 연결 확인:
```bash
docker exec pgvector psql -U postgres -d cloud -c "SELECT version();"
```

### 데이터가 동기화되지 않는 경우

```bash
# 1. Sink Connector 상태 확인
./check-connector.sh postgresql-sink-cdc-connector

# 2. Dead Letter Queue 토픽 확인
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic dlq-postgresql-sink \
  --from-beginning \
  --timeout-ms 5000

# 3. Kafka Connect 로그에서 에러 확인
docker logs kafka-connect-debezium --tail 100 | grep -i error
```

### PostgreSQL 연결 오류

```bash
# 1. 네트워크 확인
docker inspect pgvector --format '{{.HostConfig.NetworkMode}}'
docker inspect kafka-connect-debezium --format '{{.HostConfig.NetworkMode}}'

# 2. PostgreSQL이 연결을 받아들이는지 확인
docker exec pgvector psql -U postgres -c "SHOW listen_addresses;"

# 3. cloud 데이터베이스가 존재하는지 확인
docker exec pgvector psql -U postgres -c "\l" | grep cloud
```

## 📊 데이터 흐름

### CDC 이벤트 구조

Debezium이 생성하는 CDC 이벤트:

```json
{
  "payload": {
    "before": null,
    "after": {
      "id": 1,
      "username": "john_doe",
      "email": "john@example.com",
      "full_name": "John Doe"
    },
    "op": "c",
    "source": {
      "connector": "mysql",
      "name": "mariadb-cdc",
      "db": "cloud",
      "table": "users"
    }
  }
}
```

### PostgreSQL 테이블 스키마

Sink Connector가 자동으로 생성하는 테이블:

```sql
-- cdc_users
CREATE TABLE cdc_users (
    id INTEGER PRIMARY KEY,
    username VARCHAR(50),
    email VARCHAR(100),
    full_name VARCHAR(100),
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- cdc_products
CREATE TABLE cdc_products (
    id INTEGER PRIMARY KEY,
    name VARCHAR(100),
    description TEXT,
    price DECIMAL(10, 2),
    stock_quantity INTEGER,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- cdc_orders
CREATE TABLE cdc_orders (
    id INTEGER PRIMARY KEY,
    user_id INTEGER,
    product_id INTEGER,
    quantity INTEGER,
    total_price DECIMAL(10, 2),
    status VARCHAR(20),
    order_date TIMESTAMP,
    updated_at TIMESTAMP
);
```

## 🔗 관련 리소스

- [Debezium JDBC Sink Connector](https://debezium.io/documentation/reference/stable/connectors/jdbc.html)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)
- [PostgreSQL JDBC Driver](https://jdbc.postgresql.org/documentation/)

## 📝 환경 변수

스크립트에서 사용하는 환경 변수:

```bash
# Kafka Connect
export KAFKA_CONNECT_URL="http://localhost:8083"

# PostgreSQL
export PGHOST="localhost"
export PGPORT="5432"
export PGUSER="postgres"
export PGPASSWORD="postgres"
export PGDATABASE="cloud"
```

## ⚠️ 주의사항

1. **네트워크**: 모든 컨테이너가 같은 Docker 네트워크(`kafka-net`)에 있어야 합니다.

2. **순서**: Source Connector → Sink Connector 순서로 등록해야 합니다.

3. **토픽 이름**: Source Connector의 `topic.prefix`와 Sink Connector의 `topics.regex`가 일치해야 합니다.

4. **데이터베이스**: PostgreSQL에 `cloud` 데이터베이스가 미리 생성되어 있어야 합니다.

5. **테이블 자동 생성**: `auto.create=true`이므로 테이블은 자동으로 생성되지만, 스키마가 복잡한 경우 수동으로 생성하는 것이 좋습니다.

6. **Primary Key**: `primary.key.mode=record_key`는 Kafka 메시지의 키를 사용합니다. 이는 Source Connector 설정에 따라 달라집니다.

## 🎯 다음 단계

1. **모니터링 설정**: Prometheus + Grafana로 CDC 파이프라인 모니터링
2. **알림 설정**: Connector 실패 시 알림 받기
3. **성능 튜닝**: `batch.size`, `max.queue.size` 등 조정
4. **스키마 관리**: Schema Registry 도입 고려
5. **데이터 검증**: Source와 Target의 데이터 일관성 검증 스크립트 작성
