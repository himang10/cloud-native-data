# MariaDB CDC Connector 관리

이 디렉토리는 MariaDB CDC(Change Data Capture) 커넥터를 관리하기 위한 스크립트와 설정 파일을 포함합니다.

## 📋 파일 구조

```
kafka-connector/
├── README.md                           # 이 파일
├── mariadb-source-connector.json       # MariaDB CDC 커넥터 설정
├── init-database.sh                    # 샘플 데이터베이스 초기화
├── register-connector.sh               # 커넥터 등록
├── list-connectors.sh                  # 모든 커넥터 조회
├── check-connector.sh                  # 특정 커넥터 상세 정보
└── delete-connector.sh                 # 커넥터 삭제
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
```

### 2. 데이터베이스 초기화

샘플 테이블(`users`, `products`, `orders`)을 생성합니다:

```bash
./init-database.sh
```

이 스크립트는 다음을 수행합니다:
- `cloud` 데이터베이스에 3개의 테이블 생성
- 각 테이블에 샘플 데이터 삽입
- 테이블 생성 확인

### 3. 커넥터 등록

MariaDB CDC 커넥터를 Kafka Connect에 등록합니다:

```bash
./register-connector.sh mariadb-source-connector.json
```

등록이 성공하면 다음과 같은 메시지가 표시됩니다:
```
✅ 성공: 커넥터 'mariadb-source-connector'이(가) 등록되었습니다.
```

### 4. 커넥터 상태 확인

```bash
./check-connector.sh mariadb-source-connector
```

출력 예시:
```json
{
  "name": "mariadb-source-connector",
  "connector": {
    "state": "RUNNING",
    "worker_id": "kafka-connect:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "kafka-connect:8083"
    }
  ]
}
```

### 5. Kafka 토픽 확인

CDC 이벤트가 생성되는 토픽을 확인합니다:

```bash
# 토픽 목록 확인
docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list | grep mariadb-cdc

# 예상되는 토픽:
# mariadb-cdc.cloud.users
# mariadb-cdc.cloud.products
# mariadb-cdc.cloud.orders
```

### 6. CDC 이벤트 확인

특정 토픽의 메시지를 확인합니다:

```bash
# users 테이블 CDC 이벤트 확인
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic mariadb-cdc.cloud.users \
  --from-beginning \
  --max-messages 5
```

## 📚 커넥터 설정 상세

### mariadb-source-connector.json

```json
{
  "name": "mariadb-source-connector",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "database.hostname": "mariadb-cdc",
    "database.port": "3306",
    "database.user": "skala",
    "database.password": "Skala25a!23$",
    "database.server.id": "184054",
    "topic.prefix": "mariadb-cdc",
    "database.include.list": "cloud",
    "table.include.list": "cloud.users,cloud.orders,cloud.products",
    "snapshot.mode": "initial"
  }
}
```

주요 설정:
- **connector.class**: Debezium MySQL/MariaDB 커넥터 사용
- **database.hostname**: Docker 컨테이너명 (`mariadb-cdc`)
- **topic.prefix**: Kafka 토픽 접두사 (`mariadb-cdc`)
- **database.include.list**: 캡처할 데이터베이스 (`cloud`)
- **table.include.list**: 캡처할 테이블 목록
- **snapshot.mode**: 초기 스냅샷 모드 (`initial` = 첫 실행 시 모든 데이터 캡처)

## 🛠️ 스크립트 사용법

### register-connector.sh

커넥터를 등록합니다.

```bash
./register-connector.sh <connector-config.json>
```

옵션:
- 기존 커넥터가 있으면 삭제 확인 프롬프트 표시
- 등록 후 자동으로 상태 확인
- 실패 시 에러 메시지 표시

### list-connectors.sh

모든 등록된 커넥터를 조회합니다.

```bash
./list-connectors.sh
```

출력:
- 커넥터명
- 상태 (RUNNING, FAILED, PAUSED 등)
- 태스크 정보
- 설정 정보

### check-connector.sh

특정 커넥터의 상세 정보를 확인합니다.

```bash
./check-connector.sh <connector-name>
```

출력:
- 커넥터 상태
- 태스크 상태
- 설정 정보
- 추가 관리 명령어

### delete-connector.sh

커넥터를 삭제합니다.

```bash
./delete-connector.sh <connector-name>
```

주의:
- 삭제 전 확인 프롬프트 표시
- 삭제 후 남은 커넥터 목록 표시

### init-database.sh

샘플 데이터베이스를 초기화합니다.

```bash
./init-database.sh
```

생성되는 테이블:
- **users**: 사용자 정보 (id, username, email, full_name)
- **products**: 상품 정보 (id, name, description, price, stock_quantity)
- **orders**: 주문 정보 (id, user_id, product_id, quantity, total_price, status)

## 🧪 CDC 테스트

### 전체 파이프라인 통합 테스트

Source Connector와 Sink Connector를 모두 포함한 전체 CDC 파이프라인을 테스트하려면:

```bash
cd ..
./test-cdc-pipeline.sh
```

이 스크립트는 MariaDB → Kafka → PostgreSQL 전체 흐름을 자동으로 테스트합니다.

### 1. 데이터 삽입 테스트 (수동)

```bash
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud -e \
  "INSERT INTO users (username, email, full_name) VALUES ('test_user', 'test@example.com', 'Test User');"
```

### 2. 데이터 업데이트 테스트

```bash
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud -e \
  "UPDATE products SET price = 99.99 WHERE id = 1;"
```

### 3. 데이터 삭제 테스트

```bash
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud -e \
  "DELETE FROM orders WHERE id = 1;"
```

### 4. CDC 이벤트 확인

```bash
# 실시간 이벤트 모니터링
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic mariadb-cdc.cloud.users \
  --from-beginning
```

## 🔍 문제 해결

### 커넥터가 FAILED 상태인 경우

```bash
# 상세 에러 확인
./check-connector.sh mariadb-source-connector

# 커넥터 재시작
curl -X POST http://localhost:8083/connectors/mariadb-source-connector/restart

# 또는 삭제 후 재등록
./delete-connector.sh mariadb-source-connector
./register-connector.sh mariadb-source-connector.json
```

### Kafka Connect 로그 확인

```bash
docker logs kafka-connect-debezium -f
```

### MariaDB binlog 확인

```bash
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' -e "SHOW BINARY LOGS;"
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' -e "SHOW MASTER STATUS;"
```

### 토픽이 생성되지 않는 경우

```bash
# Kafka Connect 상태 확인
curl http://localhost:8083/ | jq

# 커넥터 플러그인 확인
curl http://localhost:8083/connector-plugins | jq

# MariaDB binlog 설정 확인
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' -e \
  "SHOW VARIABLES LIKE '%binlog%';"
```

## 📊 CDC 이벤트 구조

Debezium이 생성하는 CDC 이벤트는 다음과 같은 구조를 가집니다:

```json
{
  "before": null,
  "after": {
    "id": 1,
    "username": "john_doe",
    "email": "john@example.com",
    "full_name": "John Doe",
    "created_at": 1234567890000,
    "updated_at": 1234567890000
  },
  "source": {
    "version": "3.2.3.Final",
    "connector": "mysql",
    "name": "mariadb-cdc",
    "ts_ms": 1234567890000,
    "db": "cloud",
    "table": "users",
    "server_id": 1,
    "file": "mysql-bin.000001",
    "pos": 154
  },
  "op": "c",
  "ts_ms": 1234567890000
}
```

- **before**: 변경 전 데이터 (INSERT는 null)
- **after**: 변경 후 데이터
- **source**: 이벤트 메타데이터 (binlog 위치, 타임스탬프 등)
- **op**: 작업 타입 (`c`=create, `u`=update, `d`=delete, `r`=read)
- **ts_ms**: 이벤트 발생 시간

## 🔗 추가 리소스

- [Debezium MySQL Connector 문서](https://debezium.io/documentation/reference/stable/connectors/mysql.html)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)
- [Debezium 설정 가이드](https://debezium.io/documentation/reference/stable/configuration/index.html)

## 🔗 관련 디렉토리

- **../kafka-sink-connector/**: PostgreSQL Sink Connector 설정 및 관리
- **../test-cdc-pipeline.sh**: 전체 CDC 파이프라인 통합 테스트 스크립트

## 📝 환경 변수

스크립트에서 사용하는 환경 변수:

```bash
# Kafka Connect
export KAFKA_CONNECT_URL="http://localhost:8083"

# MariaDB
export MARIADB_HOST="localhost"
export MARIADB_PORT="3306"
export MARIADB_USER="skala"
export MARIADB_PASSWORD="Skala25a!23$"
export MARIADB_DATABASE="cloud"
```

## ⚠️ 주의사항

1. **Binlog 설정**: MariaDB는 binlog가 활성화되어 있어야 합니다.
   - `binlog-format=ROW`
   - `server_id=1`

2. **권한**: CDC 사용자는 `REPLICATION SLAVE`, `REPLICATION CLIENT` 권한이 필요합니다.

3. **네트워크**: 모든 컨테이너가 같은 Docker 네트워크(`kafka-net`)에 있어야 합니다.

4. **스냅샷 모드**: `snapshot.mode=initial`은 첫 실행 시 모든 데이터를 캡처합니다. 이후 실행에는 변경분만 캡처됩니다.

5. **토픽 이름**: 토픽 이름은 `{topic.prefix}.{database}.{table}` 형식입니다.
   - 예: `mariadb-cdc.cloud.users`
