# Debezium Connector Converters 설정 가이드

## 개요

### Converters란?

Kafka Connect의 **Converter**는 데이터를 Kafka에 쓰거나 읽을 때 직렬화/역직렬화를 담당합니다. Debezium 커넥터에서는 Key와 Value를 별도로 변환하며, 변환 형식은 Consumer의 처리 방식을 결정합니다.

#### Converter의 역할
- **직렬화**: Java 객체 → Kafka 저장 형식 (바이트)
- **역직렬화**: Kafka 바이트 → Consumer의 Java/JSON 객체
- **스키마 관리**: 데이터 타입, 필드 정보 유지
- **호환성**: Producer와 Consumer 간 데이터 형식 일치

### Converter 동작 흐름

```
[Debezium Source]
      ↓
[Java 객체]
      ↓
[Key Converter] ← "org.apache.kafka.connect.storage.StringConverter"
      ↓
[Kafka Key: 문자열 바이트]
      ↓
[Value Converter] ← "org.apache.kafka.connect.json.JsonConverter"
      ↓
[Kafka Value: JSON 바이트]
      ↓
[Kafka 토픽 저장]
      ↓
[Consumer]
      ↓
[역직렬화]
      ↓
[애플리케이션 객체]
```

### Converter 종류

| Converter | 형식 | 스키마 | 사용 사례 |
|-----------|------|--------|----------|
| StringConverter | 문자열 | 없음 | 단순 Key |
| JsonConverter | JSON | 선택 | 범용 |
| AvroConverter | Avro | 있음 | 스키마 진화 |
| ByteArrayConverter | 바이트 배열 | 없음 | 바이너리 데이터 |
| ProtobufConverter | Protobuf | 있음 | gRPC 호환 |

### Outbox Pattern 권장 조합

```json
{
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
```

**이유**:
1. **Key**: aggregate_id는 문자열 → StringConverter
2. **Value**: JSON 페이로드 → JsonConverter
3. **스키마 없음**: Outbox는 자유 형식 이벤트 → 스키마 비활성화

---

## Key Converter 설정

### key.converter

#### 기본 정보
- **값**: `"org.apache.kafka.connect.storage.StringConverter"`
- **타입**: String (클래스명)
- **필수**: No (기본값 사용 가능)
- **기본값**: Connect 설정에 따름

#### 상세 설명

**정의**: Kafka 메시지의 Key를 직렬화할 Converter 클래스입니다.

**Outbox Pattern에서의 Key**:
- EventRouter SMT가 `aggregate_id`를 Key로 설정
- 파티셔닝 및 순서 보장에 사용
- 일반적으로 UUID 또는 문자열 ID

**StringConverter 선택 이유**:

```sql
-- Outbox 테이블
CREATE TABLE outbox_events (
  aggregate_id VARCHAR(36),  -- UUID 문자열
  ...
);

INSERT INTO outbox_events VALUES (..., 'order-123', ...);
```

**Kafka Key**:
```
"order-123"  (UTF-8 문자열 바이트)
```

**Consumer 사용**:
```java
@KafkaListener(topics = "outbox.Order")
public void handleOrderEvent(
    @Payload OrderEvent payload,
    @Header(KafkaHeaders.RECEIVED_MESSAGE_KEY) String key) {
    
    log.info("Processing order: {}", key);  // "order-123"
}
```

**다른 Converter 비교**:

##### StringConverter (권장)
```json
"key.converter": "org.apache.kafka.connect.storage.StringConverter"
```

**Key 형식**:
```
"order-123"
```

**Consumer 역직렬화**:
```java
// Spring Kafka
@KafkaListener(topics = "outbox.Order")
public void handle(
    @Payload OrderEvent payload,
    @Header(KafkaHeaders.RECEIVED_MESSAGE_KEY) String key) {
    // key는 자동으로 String
}

// Kafka Consumer API
String key = new String(record.key(), StandardCharsets.UTF_8);
```

##### JsonConverter (비권장)
```json
"key.converter": "org.apache.kafka.connect.json.JsonConverter",
"key.converter.schemas.enable": "false"
```

**Key 형식**:
```json
"\"order-123\""  // JSON 문자열
```

**Consumer 역직렬화**:
```java
// 추가 JSON 파싱 필요
String keyJson = new String(record.key());
String key = keyJson.replaceAll("\"", "");  // 따옴표 제거
```

##### AvroConverter (고급)
```json
"key.converter": "io.confluent.connect.avro.AvroConverter",
"key.converter.schema.registry.url": "http://schema-registry:8081"
```

**장점**: 스키마 진화 지원, 타입 안정성  
**단점**: Schema Registry 필요, 복잡도 증가  
**사용 케이스**: 엔터프라이즈 환경, 복잡한 Key 구조

**설정값에 따른 동작**:

##### 시나리오 1: StringConverter (일반적)
```json
{
  "transforms.outbox.table.field.event.key": "aggregate_id",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter"
}
```

**Outbox INSERT**:
```sql
INSERT INTO outbox_events VALUES (..., 'order-123', ...);
```

**Kafka Key**:
```
바이트: [0x6F, 0x72, 0x64, 0x65, 0x72, 0x2D, 0x31, 0x32, 0x33]
문자열: "order-123"
```

**파티셔닝**:
```
hash("order-123") % 파티션 수
```

##### 시나리오 2: 숫자 ID를 문자열로
```sql
-- aggregate_id가 숫자
INSERT INTO outbox_events VALUES (..., '12345', ...);
```

**Kafka Key**:
```
"12345"  (문자열)
```

**Consumer**:
```java
String key = record.key();  // "12345"
Long id = Long.parseLong(key);  // 12345
```

---

## Value Converter 설정

### value.converter

#### 기본 정보
- **값**: `"org.apache.kafka.connect.json.JsonConverter"`
- **타입**: String (클래스명)
- **필수**: No (기본값 사용 가능)
- **기본값**: Connect 설정에 따름

#### 상세 설명

**정의**: Kafka 메시지의 Value를 직렬화할 Converter 클래스입니다.

**Outbox Pattern에서의 Value**:
- EventRouter SMT가 `payload` 필드를 확장하여 Value로 설정
- JSON 형식의 비즈니스 이벤트
- Consumer가 이해하기 쉬운 구조

**JsonConverter 선택 이유**:

```sql
-- Outbox 테이블
INSERT INTO outbox_events VALUES (
  ...,
  '{"orderId":"order-123","amount":100,"status":"PENDING"}'
);
```

**Kafka Value**:
```json
{
  "orderId": "order-123",
  "amount": 100,
  "status": "PENDING"
}
```

**Consumer 사용**:
```java
@KafkaListener(topics = "outbox.Order")
public void handleOrderEvent(OrderEvent event) {
    // Spring Kafka가 자동으로 JSON → OrderEvent 변환
    log.info("Order ID: {}, Amount: {}", 
        event.getOrderId(), event.getAmount());
}
```

**다른 Converter 비교**:

##### JsonConverter (권장)
```json
"value.converter": "org.apache.kafka.connect.json.JsonConverter",
"value.converter.schemas.enable": "false"
```

**Value 형식**:
```json
{
  "orderId": "order-123",
  "amount": 100
}
```

**장점**:
1. 범용성: 대부분의 언어/프레임워크 지원
2. 가독성: 사람이 읽을 수 있음
3. 유연성: 자유 형식 스키마

**단점**:
1. 크기: 텍스트 형식으로 용량 큼
2. 타입 안정성: 스키마 없으면 타입 보장 안 됨

##### AvroConverter (엔터프라이즈)
```json
"value.converter": "io.confluent.connect.avro.AvroConverter",
"value.converter.schema.registry.url": "http://schema-registry:8081"
```

**Value 형식**: 바이너리 + 스키마 ID

**장점**:
1. 압축: 바이너리 형식으로 작은 크기
2. 스키마 진화: 버전 관리, 호환성 체크
3. 타입 안정성: 스키마 기반 검증

**단점**:
1. Schema Registry 필요
2. 복잡한 설정
3. 디버깅 어려움 (바이너리)

**사용 케이스**: 대용량 트래픽, 스키마 진화 필요, 엔터프라이즈

##### StringConverter (특수)
```json
"value.converter": "org.apache.kafka.connect.storage.StringConverter"
```

**Value 형식**:
```
"{\"orderId\":\"order-123\",\"amount\":100}"
```

**단점**: Consumer에서 JSON 파싱 필요

**설정값에 따른 동작**:

##### 시나리오 1: JsonConverter (일반적)
```json
{
  "transforms.outbox.table.field.event.payload": "payload",
  "transforms.outbox.table.expand.json.payload": "true",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
```

**Outbox INSERT**:
```sql
INSERT INTO outbox_events (payload) VALUES (
  '{"orderId":"order-123","customerId":"cust-456","items":[...],"totalAmount":150.00}'
);
```

**Kafka Value**:
```json
{
  "orderId": "order-123",
  "customerId": "cust-456",
  "items": [...],
  "totalAmount": 150.00
}
```

**Consumer (Spring Kafka)**:
```java
public class OrderEvent {
    private String orderId;
    private String customerId;
    private List<OrderItem> items;
    private BigDecimal totalAmount;
    // getters/setters
}

@KafkaListener(topics = "outbox.Order")
public void handleOrderEvent(OrderEvent event) {
    // 자동 역직렬화
}
```

##### 시나리오 2: AvroConverter (엔터프라이즈)
```json
{
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081"
}
```

**스키마 등록** (자동 또는 수동):
```json
{
  "type": "record",
  "name": "OrderEvent",
  "fields": [
    {"name": "orderId", "type": "string"},
    {"name": "customerId", "type": "string"},
    {"name": "totalAmount", "type": "double"}
  ]
}
```

**Kafka Value**: 바이너리 + 스키마 ID

**스키마 진화**:
```json
// v2: 필드 추가 (하위 호환)
{
  "type": "record",
  "name": "OrderEvent",
  "fields": [
    {"name": "orderId", "type": "string"},
    {"name": "customerId", "type": "string"},
    {"name": "totalAmount", "type": "double"},
    {"name": "discountCode", "type": ["null", "string"], "default": null}
  ]
}
```

### value.converter.schemas.enable

#### 기본 정보
- **값**: `"false"`
- **타입**: Boolean (문자열)
- **기본값**: `true`
- **필수**: No

#### 상세 설명

**정의**: JsonConverter가 데이터와 함께 스키마 정보를 포함할지 결정합니다.

**설정값에 따른 동작**:

##### `"false"` (Outbox 권장)
```json
"value.converter": "org.apache.kafka.connect.json.JsonConverter",
"value.converter.schemas.enable": "false"
```

**Kafka Value**:
```json
{
  "orderId": "order-123",
  "amount": 100
}
```

**장점**:
1. 간결한 메시지
2. 메시지 크기 감소
3. Consumer 파싱 단순

**단점**:
1. 타입 정보 없음 (Consumer가 추론)
2. 스키마 진화 추적 어려움

**사용 케이스**:
- Outbox Pattern (자유 형식 이벤트)
- 마이크로서비스 간 이벤트
- 간단한 Consumer

##### `"true"` (기본값, CDC 용)
```json
"value.converter": "org.apache.kafka.connect.json.JsonConverter",
"value.converter.schemas.enable": "true"
```

**Kafka Value**:
```json
{
  "schema": {
    "type": "struct",
    "fields": [
      {"field": "orderId", "type": "string", "optional": false},
      {"field": "amount", "type": "int32", "optional": false}
    ]
  },
  "payload": {
    "orderId": "order-123",
    "amount": 100
  }
}
```

**장점**:
1. 타입 정보 명확
2. 스키마 진화 추적
3. 데이터 검증 가능

**단점**:
1. 메시지 크기 큼 (스키마 중복)
2. Consumer 파싱 복잡

**사용 케이스**:
- 일반 CDC (테이블 스냅샷)
- 스키마 중요한 환경
- Kafka Connect Sink Connector

**실제 비교**:

##### schemas.enable = false (Outbox 권장)
```json
// Kafka에 저장되는 Value
{
  "orderId": "order-123",
  "customerId": "cust-456",
  "items": [
    {"productId": "prod-1", "quantity": 2, "price": 50.00},
    {"productId": "prod-2", "quantity": 1, "price": 50.00}
  ],
  "totalAmount": 150.00
}
```

**메시지 크기**: ~200 bytes

**Consumer**:
```java
// Spring Kafka
@KafkaListener(topics = "outbox.Order")
public void handleOrderEvent(OrderEvent event) {
    // OrderEvent 클래스로 자동 매핑
}
```

##### schemas.enable = true
```json
{
  "schema": {
    "type": "struct",
    "fields": [
      {"field": "orderId", "type": "string", "optional": false},
      {"field": "customerId", "type": "string", "optional": false},
      {"field": "items", "type": "array", "items": {"type": "struct", ...}},
      {"field": "totalAmount", "type": "double", "optional": false}
    ],
    "optional": false,
    "name": "OrderEvent"
  },
  "payload": {
    "orderId": "order-123",
    "customerId": "cust-456",
    "items": [...],
    "totalAmount": 150.00
  }
}
```

**메시지 크기**: ~500 bytes (스키마 포함)

**Consumer**:
```java
// 스키마 추출
JSONObject message = new JSONObject(record.value());
JSONObject schema = message.getJSONObject("schema");
JSONObject payload = message.getJSONObject("payload");

// payload만 사용
OrderEvent event = mapper.readValue(payload.toString(), OrderEvent.class);
```

**Outbox Pattern 최적 설정**:

```json
{
  "transforms": "outbox",
  "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
  "transforms.outbox.table.expand.json.payload": "true",
  
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
```

**이 조합의 효과**:

**Outbox INSERT**:
```sql
INSERT INTO outbox_events VALUES (
  'evt-001',
  'Order',
  'order-123',
  'OrderCreated',
  '{"orderId":"order-123","amount":100}',
  NOW()
);
```

**Kafka 메시지 (토픽: outbox.Order)**:
```
Headers:
  event_id: evt-001
  event_type: OrderCreated
  aggregate_type: Order
  occurred_at: 2025-11-16T10:00:00Z

Key: "order-123"

Value: 
{
  "orderId": "order-123",
  "amount": 100
}
```

**Consumer (다양한 언어)**:

```java
// Java (Spring Kafka)
@KafkaListener(topics = "outbox.Order")
public void handleOrderEvent(OrderEvent event) {
    System.out.println(event.getOrderId());
}
```

```python
# Python (kafka-python)
from kafka import KafkaConsumer
import json

consumer = KafkaConsumer('outbox.Order',
                         value_deserializer=lambda m: json.loads(m.decode('utf-8')))

for message in consumer:
    event = message.value
    print(f"Order ID: {event['orderId']}")
```

```javascript
// Node.js (kafkajs)
const { Kafka } = require('kafkajs');

const kafka = new Kafka({...});
const consumer = kafka.consumer({...});

await consumer.subscribe({ topic: 'outbox.Order' });

await consumer.run({
  eachMessage: async ({ message }) => {
    const event = JSON.parse(message.value.toString());
    console.log(`Order ID: ${event.orderId}`);
  },
});
```

---

## 참고 자료

- [Kafka Connect Converters 공식 문서](https://docs.confluent.io/platform/current/connect/concepts.html#converters)
- [Kafka Connect JsonConverter](https://kafka.apache.org/documentation/#connect_included_transformation)
- [Schema Registry 가이드](https://docs.confluent.io/platform/current/schema-registry/index.html)

---

**문서 버전**: 1.0  
**최종 업데이트**: 2025-11-16
