# Outbox Pattern Connector

이 디렉토리는 Outbox Pattern을 구현하여 MariaDB의 outbox_events 테이블에서 이벤트를 읽어 Kafka 토픽으로 전송하는 Debezium Connector를 관리합니다.

## 📋 파일 구조

```
outbox-sink-connector/
├── README.md                     # 이 파일
├── init-outbox-table.sh          # Outbox 테이블 초기화
├── mariadb-outbox-connector.json # Outbox Connector 설정
├── register-connector.sh         # 커넥터 등록
├── list-connectors.sh            # 모든 커넥터 조회
├── check-connector.sh            # 특정 커넥터 상세 정보
├── delete-connector.sh           # 커넥터 삭제
├── list-outbox-topics.sh         # Outbox 토픽 목록
├── view-outbox-events.sh         # 특정 토픽의 이벤트 확인
└── publish-event.sh              # 테스트 이벤트 발행
```

## 🏗️ Outbox Pattern 아키텍처

```
Application
    ↓ (트랜잭션 내에서)
MariaDB outbox_events 테이블
    ↓ (Debezium CDC)
Kafka Topics (aggregate_type별 라우팅)
    ├── outbox.user
    ├── outbox.order
    └── outbox.product
```

### Outbox Pattern의 장점

1. **트랜잭션 보장**: 데이터베이스 트랜잭션과 이벤트 발행을 원자적으로 처리
2. **최소 1회 전달**: 이벤트가 최소한 한 번은 전달됨을 보장
3. **순서 보장**: aggregate_id별로 이벤트 순서 유지
4. **신뢰성**: 데이터베이스 트랜잭션 로그(binlog)를 사용하여 메시지 유실 방지

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

### 2. Outbox 테이블 초기화

```bash
./init-outbox-table.sh
```

생성되는 테이블 구조 (Java Entity와 동일):
```sql
CREATE TABLE outbox_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,      -- JPA @Id
    event_id CHAR(36) NOT NULL UNIQUE,         -- 이벤트 고유 ID (UUID)
    aggregate_id BIGINT NOT NULL,              -- 엔티티 식별자 (Long)
    aggregate_type VARCHAR(255) NOT NULL,      -- 라우팅 키 (user, order, product)
    event_type VARCHAR(255) NOT NULL,          -- 이벤트 타입 (created, updated, deleted)
    payload JSON NOT NULL,                     -- 이벤트 데이터
    occurred_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),  -- 밀리초 정밀도
    processed TINYINT(1) DEFAULT 0 NOT NULL    -- 처리 여부 (Boolean)
);
```

### 3. Outbox Connector 등록

```bash
./register-connector.sh mariadb-outbox-connector.json
```

- 토픽 이름: `outbox.{aggregate_type}` (예: `outbox.user`, `outbox.order`, `outbox.product`)
- 메시지 형식: JSON
- 메시지 키: `aggregate_id` (파티션 결정 및 순서 보장)

### 4. 커넥터 상태 확인

```bash
./check-connector.sh mariadb-outbox-connector
```

### 5. Kafka 토픽 확인

```bash
./list-outbox-topics.sh
```

예상되는 토픽:
- `outbox.user`
- `outbox.order`
- `outbox.product`

### 6. 이벤트 확인

```bash
./view-outbox-events.sh outbox.user
```

## 📚 Outbox Connector 설정 상세

### mariadb-outbox-connector.json

```json
{
  "name": "mariadb-outbox-connector",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "table.include.list": "cloud.outbox_events",
    
    "transforms": "outbox",
    "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
    "transforms.outbox.route.by.field": "aggregate_type",
    "transforms.outbox.route.topic.replacement": "outbox.${routedByValue}"
  }
}
```

주요 설정:
- **transforms.outbox.type**: Outbox Event Router SMT (Single Message Transform)
- **route.by.field**: `aggregate_type` 필드로 토픽 라우팅
- **route.topic.replacement**: 토픽 이름 형식 지정
- **table.field.event.key**: `aggregate_id`를 Kafka 메시지 키로 사용

### EventRouter 동작 방식

1. **outbox_events 테이블 감지**: Debezium이 테이블의 INSERT 이벤트 캡처
2. **이벤트 추출**: `event_id`, `aggregate_type`, `aggregate_id`, `event_type`, `payload` 추출
3. **토픽 라우팅**: `aggregate_type` 값에 따라 토픽 결정
   - `aggregate_type='user'` → `outbox.user`
   - `aggregate_type='order'` → `outbox.order`
4. **메시지 생성**:
   - Key: `aggregate_id`
   - Value: `payload` (JSON)
   - Headers: `event_id`, `event_type`, `aggregate_type`, `occurred_at`

## 🛠️ 스크립트 사용법

### init-outbox-table.sh

Outbox 테이블과 샘플 데이터를 생성합니다.

```bash
./init-outbox-table.sh
```

생성되는 샘플 이벤트:
- 2개의 UserCreated 이벤트
- 2개의 OrderCreated 이벤트
- 1개의 ProductCreated 이벤트

### register-connector.sh

Outbox Connector를 등록합니다.

```bash
./register-connector.sh <connector-config.json>
```

### list-connectors.sh

등록된 모든 커넥터를 조회합니다.

```bash
./list-connectors.sh
```

### check-connector.sh

특정 커넥터의 상세 정보를 확인합니다.

```bash
./check-connector.sh mariadb-outbox-connector
```

### delete-connector.sh

커넥터를 삭제합니다.

```bash
./delete-connector.sh mariadb-outbox-connector
```

### list-outbox-topics.sh

Outbox 관련 모든 Kafka 토픽을 조회합니다.

```bash
./list-outbox-topics.sh
```

출력:
- Outbox 이벤트 토픽
- 스키마 히스토리 토픽
- 에러 토픽

### view-outbox-events.sh

특정 토픽의 이벤트를 확인합니다.

```bash
./view-outbox-events.sh outbox.user
./view-outbox-events.sh outbox.order
./view-outbox-events.sh outbox.product
```

### publish-event.sh

테스트 이벤트를 발행합니다 (대화형).

```bash
./publish-event.sh
```

선택 가능한 이벤트:
1. UserCreated
2. OrderCreated
3. ProductCreated
4. UserUpdated
5. OrderStatusChanged

## 🧪 사용 예제

### 1. 새 사용자 생성 이벤트

```bash
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud <<EOSQL
INSERT INTO outbox_events (event_id, aggregate_type, aggregate_id, event_type, payload)
VALUES (
    UUID(),
    'user',
    'user-123',
    'UserCreated',
    JSON_OBJECT(
        'userId', 'user-123',
        'username', 'john_doe',
        'email', 'john@example.com',
        'fullName', 'John Doe',
        'createdAt', NOW()
    )
);
EOSQL
```

### 2. 주문 상태 변경 이벤트

```bash
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud <<EOSQL
INSERT INTO outbox_events (event_id, aggregate_type, aggregate_id, event_type, payload)
VALUES (
    UUID(),
    'order',
    'order-456',
    'OrderStatusChanged',
    JSON_OBJECT(
        'orderId', 'order-456',
        'oldStatus', 'pending',
        'newStatus', 'shipped',
        'changedAt', NOW()
    )
);
EOSQL
```

### 3. Kafka에서 이벤트 확인

```bash
# 사용자 이벤트 확인
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic outbox.user \
  --from-beginning \
  --max-messages 5

# 헤더 포함 확인
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic outbox.order \
  --from-beginning \
  --property print.headers=true \
  --property print.timestamp=true
```

## 📊 메시지 구조

### Kafka 메시지

**Value (Payload):**
```json
{
  "userId": 1,
  "username": "john_doe",
  "email": "john@example.com",
  "fullName": "John Doe",
  "createdAt": "2025-11-16T05:30:00Z"
}
```

**Key:** `"1"` (aggregate_id를 문자열로 변환)

**Headers:**
- `event_id`: "550e8400-e29b-41d4-a716-446655440000"
- `event_type`: "created"
- `aggregate_type`: "user"
- `aggregate_id`: "1"
- `occurred_at`: "2025-11-16T05:30:00.123"

## 🔍 문제 해결

### 커넥터가 FAILED 상태인 경우

```bash
# 상세 에러 확인
./check-connector.sh mariadb-outbox-connector

# Kafka Connect 로그 확인
docker logs kafka-connect-debezium -f | grep -i error

# 커넥터 재시작
curl -X POST http://localhost:8083/connectors/mariadb-outbox-connector/restart
```

### 토픽이 생성되지 않는 경우

1. Outbox 테이블에 데이터가 있는지 확인:
```bash
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud \
  -e "SELECT * FROM outbox_events ORDER BY occurred_at DESC LIMIT 5;"
```

2. 커넥터 상태 확인:
```bash
./check-connector.sh mariadb-outbox-connector
```

3. MariaDB binlog 설정 확인:
```bash
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' \
  -e "SHOW VARIABLES LIKE '%binlog%';"
```

### 이벤트가 라우팅되지 않는 경우

EventRouter 설정 확인:
```bash
curl http://localhost:8083/connectors/mariadb-outbox-connector/config | jq '{
  transforms: .transforms,
  route_by_field: ."transforms.outbox.route.by.field",
  route_topic: ."transforms.outbox.route.topic.replacement"
}'
```

### Dead Letter Queue 확인

```bash
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic outbox-connector-errors \
  --from-beginning \
  --timeout-ms 5000
```

## 🎯 Best Practices

### 1. 이벤트 설계

```sql
-- ✓ 좋은 예: 명확한 이벤트 타입과 완전한 페이로드
INSERT INTO outbox_events (event_id, aggregate_type, aggregate_id, event_type, payload)
VALUES (
    UUID(),
    'order',
    'order-123',
    'OrderCreated',  -- 명확한 과거형 이벤트
    JSON_OBJECT(
        'orderId', 'order-123',
        'userId', 'user-456',
        'items', JSON_ARRAY(...),
        'totalAmount', 199.99,
        'createdAt', NOW()
    )
);

-- ✗ 나쁜 예: 불명확한 이벤트 타입
INSERT INTO outbox_events (...)
VALUES (..., 'order', 'order-123', 'update', ...);  -- 무엇이 업데이트되었는지 불명확
```

### 2. Aggregate Type 일관성

```bash
# ✓ 좋은 예: 소문자, 단수형
aggregate_type: 'user', 'order', 'product'

# ✗ 나쁜 예: 대문자, 복수형, 혼합
aggregate_type: 'User', 'orders', 'product_items'
```

### 3. 트랜잭션 보장

```sql
-- ✓ 좋은 예: 비즈니스 로직과 이벤트를 같은 트랜잭션에서 처리
START TRANSACTION;

-- 비즈니스 데이터 저장
INSERT INTO users (id, username, email) VALUES ('user-123', 'john', 'john@example.com');

-- 이벤트 발행
INSERT INTO outbox_events (event_id, aggregate_type, aggregate_id, event_type, payload)
VALUES (UUID(), 'user', 'user-123', 'UserCreated', JSON_OBJECT('userId', 'user-123', ...));

COMMIT;
```

### 4. 멱등성 보장

Consumer 측에서 `event_id`를 사용하여 중복 처리 방지:

```python
# Consumer 예제 (Python)
processed_events = set()  # 또는 Redis, Database

def handle_event(event):
    event_id = event.headers['event_id']
    
    if event_id in processed_events:
        return  # 이미 처리된 이벤트
    
    # 이벤트 처리
    process_user_created(event.value)
    
    # 처리 완료 기록
    processed_events.add(event_id)
```

## 🔗 관련 리소스

- [Debezium Outbox Event Router](https://debezium.io/documentation/reference/stable/transformations/outbox-event-router.html)
- [Outbox Pattern](https://microservices.io/patterns/data/transactional-outbox.html)
- [Kafka Topic Naming Conventions](https://cnr.sh/essays/how-paint-bike-shed-kafka-topic-naming-conventions)

## 📝 환경 변수

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

1. **Server ID 충돌**: 각 커넥터는 고유한 `database.server.id`를 가져야 합니다.

2. **토픽 이름**: `aggregate_type` 값이 토픽 이름의 일부가 되므로 소문자와 하이픈만 사용 권장.

3. **Payload 크기**: JSON payload가 너무 크면 Kafka 메시지 크기 제한에 걸릴 수 있음.

4. **순서 보장**: 같은 `aggregate_id`의 이벤트는 같은 파티션으로 전송되어 순서 보장.

5. **메시지 삭제**: Outbox 테이블의 레코드는 자동으로 삭제되지 않음. 주기적인 정리 필요.

## 🎯 다음 단계

1. **Consumer 구현**: 각 토픽에 대한 Consumer 애플리케이션 개발
2. **모니터링**: Prometheus + Grafana로 Outbox 이벤트 메트릭 수집
3. **자동 정리**: 처리된 이벤트 자동 삭제 스케줄러 구현
4. **스키마 레지스트리**: Avro/Protobuf 스키마 관리
5. **재시도 로직**: Consumer 측 에러 처리 및 재시도 메커니즘
