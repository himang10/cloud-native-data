# Debezium Outbox Connector Transforms 설정 가이드

## 개요

### Transforms란?

Kafka Connect의 **Single Message Transform (SMT)**는 커넥터가 소스에서 읽은 레코드를 Kafka에 쓰기 전에 변환하는 메커니즘입니다. Debezium Outbox Pattern에서는 **EventRouter SMT**를 사용하여 Outbox 테이블의 레코드를 비즈니스 이벤트로 변환합니다.

#### Transforms의 역할
- **데이터 변환**: Outbox 테이블 레코드 → 도메인 이벤트
- **토픽 라우팅**: `aggregate_type` 기반 동적 토픽 생성
- **메타데이터 추출**: 이벤트 ID, 타입 등을 Kafka 헤더로 이동
- **페이로드 확장**: JSON 페이로드를 최상위 필드로 전개

### EventRouter SMT란?

Debezium이 제공하는 Outbox Pattern 전용 SMT입니다.

**동작 흐름**:
```
[Outbox 테이블]
┌─────────────────────────────────────────────────────────┐
│ event_id: "evt-001"                                     │
│ aggregate_type: "Order"                                 │
│ aggregate_id: "order-123"                               │
│ event_type: "OrderCreated"                              │
│ payload: {"orderId":"order-123","amount":100}           │
│ occurred_at: "2025-11-16T10:00:00"                      │
└─────────────────────────────────────────────────────────┘
                    ↓
         [EventRouter SMT 변환]
                    ↓
[Kafka 토픽: outbox.Order]
┌─────────────────────────────────────────────────────────┐
│ Headers:                                                 │
│   event_id: "evt-001"                                   │
│   event_type: "OrderCreated"                            │
│   aggregate_type: "Order"                               │
│   aggregate_id: "order-123"                             │
│   occurred_at: "2025-11-16T10:00:00"                    │
│                                                          │
│ Key: "order-123"                                        │
│                                                          │
│ Value:                                                   │
│ {                                                        │
│   "orderId": "order-123",                               │
│   "amount": 100                                         │
│ }                                                        │
└─────────────────────────────────────────────────────────┘
```

### EventRouter 없이 사용할 경우

**일반 CDC 변환 결과**:
```json
{
  "before": null,
  "after": {
    "event_id": "evt-001",
    "aggregate_type": "Order",
    "aggregate_id": "order-123",
    "event_type": "OrderCreated",
    "payload": "{\"orderId\":\"order-123\",\"amount\":100}",
    "occurred_at": 1700121600000
  },
  "source": {
    "version": "2.4.0.Final",
    "connector": "mysql",
    "name": "mariadb-outbox-source-server",
    "ts_ms": 1700121600000,
    "db": "cloud",
    "table": "outbox_events"
  },
  "op": "c",
  "ts_ms": 1700121600123
}
```

**문제점**:
1. CDC 메타데이터 노출 (before, after, source, op)
2. 페이로드가 JSON 문자열로 포함
3. 모든 이벤트가 단일 토픽 (`mariadb-outbox-source-server.cloud.outbox_events`)
4. 비즈니스 이벤트로 사용하기 어려운 구조

**EventRouter 적용 후**:
```json
{
  "orderId": "order-123",
  "amount": 100
}
```

**장점**:
1. 깔끔한 비즈니스 이벤트
2. aggregate_type별로 독립된 토픽
3. 메타데이터는 Kafka 헤더로 분리
4. Consumer가 이해하기 쉬운 구조

---

## Transforms 설정 필드

### transforms

#### 기본 정보
- **값**: `"outbox"`
- **타입**: String
- **필수**: Yes (Outbox Pattern 사용 시)

#### 상세 설명

**정의**: 적용할 transform의 이름을 지정합니다. 여러 transform을 적용할 경우 쉼표로 구분합니다.

**예시**:
```json
// 단일 transform
"transforms": "outbox"

// 다중 transform
"transforms": "outbox,flattenStruct,replaceField"
```

**Outbox Pattern**: `"outbox"` 이름은 관례적으로 사용되며, 이후 설정에서 `transforms.outbox.*` 형식으로 참조됩니다.

### transforms.outbox.type

#### 기본 정보
- **값**: `"io.debezium.transforms.outbox.EventRouter"`
- **타입**: String (클래스명)
- **필수**: Yes

#### 상세 설명

**정의**: 사용할 SMT의 전체 클래스명입니다.

**Debezium EventRouter**: Outbox Pattern 전용 SMT로, Debezium이 제공합니다.

**다른 SMT 예시**:
```json
// Kafka Connect 기본 제공
"transforms.flatten.type": "org.apache.kafka.connect.transforms.Flatten$Value"
"transforms.extract.type": "org.apache.kafka.connect.transforms.ExtractField$Key"

// Debezium 제공
"transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
"transforms.route.type": "io.debezium.transforms.ByLogicalTableRouter"
```

---

## Outbox 테이블 필드 매핑

### transforms.outbox.table.field.event.id

#### 기본 정보
- **값**: `"event_id"`
- **타입**: String
- **기본값**: `id`
- **필수**: No

#### 상세 설명

**정의**: Outbox 테이블에서 이벤트 ID를 저장하는 컬럼명입니다.

**용도**:
- 이벤트 고유 식별자
- 멱등성 보장 (중복 처리 방지)
- 이벤트 추적 및 디버깅

**테이블 매핑**:
```sql
CREATE TABLE outbox_events (
  event_id VARCHAR(36) PRIMARY KEY,  -- 이 컬럼
  ...
);
```

**사용 예시**:
```json
// 기본 컬럼명 사용
"transforms.outbox.table.field.event.id": "id"

// 커스텀 컬럼명
"transforms.outbox.table.field.event.id": "event_id"
"transforms.outbox.table.field.event.id": "uuid"
"transforms.outbox.table.field.event.id": "message_id"
```

### transforms.outbox.table.field.event.key

#### 기본 정보
- **값**: `"aggregate_id"`
- **타입**: String
- **기본값**: `aggregateid`
- **필수**: No

#### 상세 설명

**정의**: Kafka 메시지의 Key로 사용할 Outbox 테이블 컬럼명입니다.

**용도**:
- Kafka 파티셔닝 (같은 aggregate_id는 같은 파티션)
- 순서 보장 (같은 aggregate의 이벤트는 순서대로 처리)
- Compaction 키 (로그 압축 시 사용)

**테이블 매핑**:
```sql
CREATE TABLE outbox_events (
  aggregate_id VARCHAR(36),  -- 이 컬럼
  ...
);
```

**Kafka 메시지**:
```json
{
  "key": "order-123",  // aggregate_id 값
  "value": {...},
  "headers": {...}
}
```

**파티셔닝 효과**:
```
Order aggregate_id: "order-123"
→ hash("order-123") % 3 = Partition 1

Order aggregate_id: "order-456"
→ hash("order-456") % 3 = Partition 2

Order aggregate_id: "order-789"
→ hash("order-789") % 3 = Partition 1
```

### transforms.outbox.table.field.event.type

#### 기본 정보
- **값**: `"event_type"`
- **타입**: String
- **기본값**: `type`
- **필수**: No

#### 상세 설명

**정의**: 이벤트 타입을 저장하는 Outbox 테이블 컬럼명입니다.

**용도**:
- 이벤트 종류 구분 (OrderCreated, OrderCancelled 등)
- Consumer의 이벤트 핸들러 라우팅
- 이벤트 필터링

**테이블 매핑**:
```sql
CREATE TABLE outbox_events (
  event_type VARCHAR(255),  -- 이 컬럼
  ...
);
```

**예시 값**:
```
OrderCreated
OrderUpdated
OrderCancelled
OrderShipped
PaymentProcessed
```

**Consumer 활용**:
```java
// Spring Cloud Stream
@StreamListener("outbox.Order")
public void handleOrderEvent(
    @Payload OrderEvent event,
    @Header("event_type") String eventType) {
    
    switch(eventType) {
        case "OrderCreated":
            handleOrderCreated(event);
            break;
        case "OrderCancelled":
            handleOrderCancelled(event);
            break;
    }
}
```

### transforms.outbox.table.field.event.payload

#### 기본 정보
- **값**: `"payload"`
- **타입**: String
- **기본값**: `payload`
- **필수**: No

#### 상세 설명

**정의**: 이벤트 페이로드(비즈니스 데이터)를 저장하는 Outbox 테이블 컬럼명입니다.

**용도**:
- 비즈니스 데이터 전달
- JSON 형식으로 저장
- EventRouter가 이 필드를 Kafka Value로 변환

**테이블 매핑**:
```sql
CREATE TABLE outbox_events (
  payload JSON,  -- 이 컬럼 (또는 TEXT)
  ...
);
```

**저장 예시**:
```json
{
  "orderId": "order-123",
  "customerId": "cust-456",
  "items": [
    {"productId": "prod-1", "quantity": 2},
    {"productId": "prod-2", "quantity": 1}
  ],
  "totalAmount": 150.00,
  "status": "PENDING"
}
```

**Kafka Value 변환**:
```json
// transforms.outbox.table.expand.json.payload: true
{
  "orderId": "order-123",
  "customerId": "cust-456",
  "items": [...]
}

// transforms.outbox.table.expand.json.payload: false
{
  "payload": "{\"orderId\":\"order-123\",...}"
}
```

### transforms.outbox.table.expand.json.payload

#### 기본 정보
- **값**: `"true"`
- **타입**: Boolean (문자열)
- **기본값**: `false`
- **필수**: No (하지만 권장)

#### 상세 설명

**정의**: JSON 페이로드를 Kafka 메시지의 최상위 필드로 확장할지 결정합니다.

**설정값에 따른 동작**:

##### `"true"` (권장)
```json
"transforms.outbox.table.expand.json.payload": "true"
```

**Outbox 테이블**:
```sql
INSERT INTO outbox_events VALUES (
  'evt-001',
  'Order',
  'order-123',
  'OrderCreated',
  '{"orderId":"order-123","amount":100}'
);
```

**Kafka Value**:
```json
{
  "orderId": "order-123",
  "amount": 100
}
```

**장점**:
1. Consumer가 직접 필드 접근 가능
2. JSON 파싱 불필요
3. 스키마 진화 가능

##### `"false"` (기본값)
```json
"transforms.outbox.table.expand.json.payload": "false"
```

**Kafka Value**:
```json
{
  "payload": "{\"orderId\":\"order-123\",\"amount\":100}"
}
```

**단점**:
1. Consumer에서 추가 JSON 파싱 필요
2. 중첩 구조
3. 스키마 활용 불가

**실제 비교**:

##### 시나리오 1: expand = true (권장)
```java
// Consumer 코드
@KafkaListener(topics = "outbox.Order")
public void handleOrder(OrderEvent event) {
    String orderId = event.getOrderId();  // 직접 접근
    int amount = event.getAmount();
}
```

##### 시나리오 2: expand = false
```java
// Consumer 코드
@KafkaListener(topics = "outbox.Order")
public void handleOrder(String message) {
    JSONObject wrapper = new JSONObject(message);
    String payloadStr = wrapper.getString("payload");  // 1차 파싱
    JSONObject payload = new JSONObject(payloadStr);   // 2차 파싱
    String orderId = payload.getString("orderId");
}
```

---

## 토픽 라우팅 설정

### transforms.outbox.route.by.field

#### 기본 정보
- **값**: `"aggregate_type"`
- **타입**: String
- **기본값**: `aggregatetype`
- **필수**: No

#### 상세 설명

**정의**: 토픽 이름을 결정할 Outbox 테이블 컬럼명입니다.

**용도**:
- aggregate_type별로 독립된 Kafka 토픽 생성
- 도메인 중심 이벤트 스트림
- Consumer의 선택적 구독

**테이블 매핑**:
```sql
CREATE TABLE outbox_events (
  aggregate_type VARCHAR(255),  -- 이 컬럼
  ...
);
```

**동작 예시**:

```sql
-- Order 이벤트
INSERT INTO outbox_events VALUES (
  'evt-001', 'Order', 'order-123', 'OrderCreated', ...
);
→ Kafka 토픽: outbox.Order

-- Payment 이벤트
INSERT INTO outbox_events VALUES (
  'evt-002', 'Payment', 'pay-456', 'PaymentProcessed', ...
);
→ Kafka 토픽: outbox.Payment

-- Shipment 이벤트
INSERT INTO outbox_events VALUES (
  'evt-003', 'Shipment', 'ship-789', 'ShipmentDispatched', ...
);
→ Kafka 토픽: outbox.Shipment
```

**토픽 분리 효과**:
```
[outbox.Order]
- OrderCreated
- OrderUpdated
- OrderCancelled

[outbox.Payment]
- PaymentProcessed
- PaymentRefunded

[outbox.Shipment]
- ShipmentDispatched
- ShipmentDelivered
```

**Consumer 구독**:
```java
// Order만 구독
@KafkaListener(topics = "outbox.Order")
public void handleOrderEvents(OrderEvent event) { ... }

// Payment만 구독
@KafkaListener(topics = "outbox.Payment")
public void handlePaymentEvents(PaymentEvent event) { ... }

// 모든 Outbox 이벤트 구독
@KafkaListener(topics = "outbox.*", topicPattern = true)
public void handleAllEvents(GenericEvent event) { ... }
```

### transforms.outbox.route.topic.replacement

#### 기본 정보
- **값**: `"outbox.${routedByValue}"`
- **타입**: String (패턴)
- **기본값**: `${routedByValue}`
- **필수**: No

#### 상세 설명

**정의**: 토픽 이름 생성 패턴입니다. `${routedByValue}`는 `route.by.field`의 값으로 대체됩니다.

**패턴 형식**:
```
{prefix}.${routedByValue}.{suffix}
```

**예시**:

```json
// 패턴 1: 단순 aggregate_type
"transforms.outbox.route.topic.replacement": "${routedByValue}"

aggregate_type: "Order" → 토픽: "Order"
aggregate_type: "Payment" → 토픽: "Payment"

// 패턴 2: outbox 접두사 (권장)
"transforms.outbox.route.topic.replacement": "outbox.${routedByValue}"

aggregate_type: "Order" → 토픽: "outbox.Order"
aggregate_type: "Payment" → 토픽: "outbox.Payment"

// 패턴 3: 환경별 구분
"transforms.outbox.route.topic.replacement": "prod.events.${routedByValue}"

aggregate_type: "Order" → 토픽: "prod.events.Order"

// 패턴 4: 도메인별 그룹화
"transforms.outbox.route.topic.replacement": "ecommerce.${routedByValue}.events"

aggregate_type: "Order" → 토픽: "ecommerce.Order.events"
```

**네이밍 권장사항**:

```json
// 개발 환경
"transforms.outbox.route.topic.replacement": "dev.outbox.${routedByValue}"

// 스테이징 환경
"transforms.outbox.route.topic.replacement": "staging.outbox.${routedByValue}"

// 프로덕션 환경
"transforms.outbox.route.topic.replacement": "prod.outbox.${routedByValue}"
```

**토픽 구조 비교**:

| aggregate_type | 패턴 | 최종 토픽 |
|----------------|------|-----------|
| Order | `${routedByValue}` | `Order` |
| Order | `outbox.${routedByValue}` | `outbox.Order` |
| Order | `${routedByValue}.events` | `Order.events` |
| Order | `prod.${routedByValue}` | `prod.Order` |

**실제 시나리오**:

##### 시나리오 1: 멀티 환경 운영
```json
// 개발
{
  "name": "dev-outbox-connector",
  "transforms.outbox.route.topic.replacement": "dev.outbox.${routedByValue}"
}

// 프로덕션
{
  "name": "prod-outbox-connector",
  "transforms.outbox.route.topic.replacement": "prod.outbox.${routedByValue}"
}
```

**결과**:
```
개발: dev.outbox.Order, dev.outbox.Payment
프로덕션: prod.outbox.Order, prod.outbox.Payment
```

##### 시나리오 2: 도메인별 격리
```json
// 주문 도메인
"transforms.outbox.route.topic.replacement": "order-domain.${routedByValue}"

// 결제 도메인
"transforms.outbox.route.topic.replacement": "payment-domain.${routedByValue}"
```

---

## 추가 필드 배치

### transforms.outbox.table.fields.additional.placement

#### 기본 정보
- **값**: `"event_id:header,event_type:header,aggregate_type:header,aggregate_id:header,occurred_at:header"`
- **타입**: String (쉼표 구분 리스트)
- **필수**: No

#### 상세 설명

**정의**: Outbox 테이블의 추가 컬럼을 Kafka 메시지의 어디에 배치할지 지정합니다.

**형식**:
```
{컬럼명}:{위치},{컬럼명}:{위치},...
```

**위치 옵션**:
- `header`: Kafka 메시지 헤더
- `envelope`: 메시지 Value의 최상위 객체 (사용 빈도 낮음)

**예시**:

```json
"transforms.outbox.table.fields.additional.placement": 
  "event_id:header,event_type:header,aggregate_type:header,aggregate_id:header,occurred_at:header"
```

**Kafka 메시지 구조**:

```json
{
  "headers": {
    "event_id": "evt-001",
    "event_type": "OrderCreated",
    "aggregate_type": "Order",
    "aggregate_id": "order-123",
    "occurred_at": "2025-11-16T10:00:00Z"
  },
  "key": "order-123",
  "value": {
    "orderId": "order-123",
    "amount": 100
  }
}
```

**헤더로 배치하는 이유**:

1. **메타데이터 분리**: 비즈니스 데이터(value)와 메타데이터(header) 구분
2. **필터링 용이**: Consumer가 Value 역직렬화 없이 헤더만으로 필터링
3. **라우팅 효율**: 메시지 브로커나 게이트웨이가 헤더 기반 라우팅 가능
4. **페이로드 간결**: Value는 순수 비즈니스 데이터만 포함

**Consumer 활용**:

```java
@KafkaListener(topics = "outbox.Order")
public void handleOrderEvent(
    @Payload OrderEvent payload,
    @Header("event_id") String eventId,
    @Header("event_type") String eventType,
    @Header("aggregate_type") String aggregateType,
    @Header("occurred_at") String occurredAt) {
    
    // 헤더로 사전 필터링
    if ("OrderCancelled".equals(eventType)) {
        handleCancellation(payload);
    }
    
    // 이벤트 추적
    log.info("Processing event: {} at {}", eventId, occurredAt);
}
```

**다양한 배치 전략**:

##### 전략 1: 모두 헤더 (권장)
```json
"transforms.outbox.table.fields.additional.placement": 
  "event_id:header,event_type:header,aggregate_type:header,occurred_at:header"
```

**장점**: 깔끔한 페이로드, 효율적인 필터링

##### 전략 2: 일부만 헤더
```json
"transforms.outbox.table.fields.additional.placement": 
  "event_id:header,event_type:header"
```

**결과**:
- 헤더: event_id, event_type
- Value: aggregate_type, occurred_at 포함

##### 전략 3: envelope 사용 (특수 케이스)
```json
"transforms.outbox.table.fields.additional.placement": 
  "event_id:envelope,event_type:envelope"
```

**결과**:
```json
{
  "value": {
    "event_id": "evt-001",
    "event_type": "OrderCreated",
    "orderId": "order-123",
    "amount": 100
  }
}
```

**Outbox 테이블 설계와의 관계**:

```sql
CREATE TABLE outbox_events (
  event_id VARCHAR(36) PRIMARY KEY,      -- header로 추출
  aggregate_type VARCHAR(255),           -- header로 추출
  aggregate_id VARCHAR(36),              -- key로 사용 + header로 추출
  event_type VARCHAR(255),               -- header로 추출
  payload JSON,                          -- value로 확장
  occurred_at TIMESTAMP,                 -- header로 추출
  
  -- 이 컬럼들은 Kafka에 포함되지 않음
  processed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**전체 설정 예시**:

```json
{
  "transforms.outbox.table.field.event.id": "event_id",
  "transforms.outbox.table.field.event.key": "aggregate_id",
  "transforms.outbox.table.field.event.type": "event_type",
  "transforms.outbox.table.field.event.payload": "payload",
  "transforms.outbox.table.expand.json.payload": "true",
  
  "transforms.outbox.route.by.field": "aggregate_type",
  "transforms.outbox.route.topic.replacement": "outbox.${routedByValue}",
  
  "transforms.outbox.table.fields.additional.placement": 
    "event_id:header,event_type:header,aggregate_type:header,aggregate_id:header,occurred_at:header"
}
```

**이 설정의 최종 결과**:

**Outbox INSERT**:
```sql
INSERT INTO outbox_events VALUES (
  'evt-001',              -- event_id
  'Order',                -- aggregate_type
  'order-123',            -- aggregate_id
  'OrderCreated',         -- event_type
  '{"orderId":"order-123","customerId":"cust-456","amount":100}',
  '2025-11-16 10:00:00'   -- occurred_at
);
```

**Kafka 토픽: outbox.Order**:
```json
{
  "headers": {
    "event_id": "evt-001",
    "event_type": "OrderCreated",
    "aggregate_type": "Order",
    "aggregate_id": "order-123",
    "occurred_at": "2025-11-16T10:00:00Z"
  },
  "key": "order-123",
  "value": {
    "orderId": "order-123",
    "customerId": "cust-456",
    "amount": 100
  }
}
```

---

## 참고 자료

- [Debezium Outbox Event Router 공식 문서](https://debezium.io/documentation/reference/stable/transformations/outbox-event-router.html)
- [Kafka Connect Single Message Transforms](https://kafka.apache.org/documentation/#connect_transforms)
- [Outbox Pattern 설명](https://microservices.io/patterns/data/transactional-outbox.html)

---

**문서 버전**: 1.0  
**최종 업데이트**: 2025-11-16
