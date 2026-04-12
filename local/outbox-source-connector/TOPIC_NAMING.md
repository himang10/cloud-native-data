# Outbox Topic 명명 규칙

## 📌 토픽 이름 형식

Outbox Pattern에서 생성되는 Kafka 토픽은 **소문자**로 명명됩니다:

```
outbox.{aggregate_type}
```

### ✅ 올바른 예시

- `outbox.user` - 사용자 관련 이벤트
- `outbox.order` - 주문 관련 이벤트
- `outbox.product` - 상품 관련 이벤트

### ❌ 잘못된 예시 (사용하지 않음)

- ~~`outbox.USER`~~ - 대문자 사용 금지
- ~~`outbox.Order`~~ - 카멜케이스 사용 금지
- ~~`outbox.PRODUCT`~~ - 대문자 사용 금지

## 🔧 구현 방법

### 1. 데이터베이스 테이블

`outbox_events` 테이블의 `aggregate_type` 컬럼에 **소문자** 값을 저장:

```sql
INSERT INTO outbox_events (event_id, aggregate_id, aggregate_type, event_type, payload, processed) 
VALUES 
    (UUID(), 1, 'user', 'created', '{"userId": 1, "username": "john"}', 0),
    (UUID(), 1001, 'order', 'created', '{"orderId": 1001, "status": "pending"}', 0),
    (UUID(), 101, 'product', 'created', '{"productId": 101, "name": "Laptop"}', 0);
```

### 2. Debezium EventRouter 설정

`mariadb-outbox-connector.json`:

```json
{
  "transforms.outbox.route.by.field": "aggregate_type",
  "transforms.outbox.route.topic.replacement": "outbox.${routedByValue}"
}
```

- `route.by.field`: aggregate_type 컬럼 값으로 라우팅
- `route.topic.replacement`: 토픽 이름 패턴 (값이 그대로 사용됨)

### 3. Java Entity

`OutboxEvent.java`에서 소문자 상수 사용 권장:

```java
public class OutboxEvent {
    @Column(name = "aggregate_type")
    private String aggregateType;  // "user", "order", "product"
    
    // 상수 정의 예시
    public static final String AGGREGATE_TYPE_USER = "user";
    public static final String AGGREGATE_TYPE_ORDER = "order";
    public static final String AGGREGATE_TYPE_PRODUCT = "product";
}
```

## 📊 현재 토픽 목록

```bash
$ docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list | grep "^outbox\."

outbox.order
outbox.product
outbox.user
```

## 🎯 명명 규칙 선택 이유

### 1. Kafka 표준 관례

Kafka 커뮤니티에서는 토픽 이름에 **소문자와 하이픈(-) 또는 점(.)** 사용을 권장:

- ✅ `outbox.user`
- ✅ `payment-events`
- ❌ `OutboxUser` (카멜케이스)
- ❌ `OUTBOX.USER` (대문자)

### 2. 크로스 플랫폼 호환성

- Linux/Unix 시스템에서는 대소문자를 구분
- 일부 시스템에서는 대소문자 혼용 시 문제 발생 가능
- 소문자 통일로 일관성 유지

### 3. 읽기 편의성

- `outbox.user` (명확하고 읽기 쉬움)
- `OUTBOX.USER` (시각적으로 강조가 과함)
- `outbox.User` (불필요한 대문자 사용)

### 4. 자동화 스크립트 호환

셸 스크립트나 CI/CD 파이프라인에서 대소문자 처리가 단순화됨:

```bash
# 간단한 패턴 매칭
for topic in user order product; do
  echo "Processing outbox.$topic"
done
```

## 🔄 기존 대문자 토픽 마이그레이션

만약 이미 대문자 토픽이 생성되어 있다면:

```bash
# 1. 대문자 토픽 삭제
docker exec kafka kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --delete --topic outbox.USER,outbox.ORDER,outbox.PRODUCT

# 2. outbox_events 테이블의 aggregate_type을 소문자로 업데이트
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud <<SQL
UPDATE outbox_events 
SET aggregate_type = LOWER(aggregate_type);
SQL

# 3. 커넥터 재시작
cd /path/to/outbox-sink-connector
echo "y" | ./delete-connector.sh mariadb-outbox-connector
./register-connector.sh mariadb-outbox-connector.json

# 4. 새로운 소문자 토픽 확인
docker exec kafka kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list | grep "^outbox\."
```

## 📝 베스트 프랙티스

### 1. 코드에서 상수 사용

```java
// ✅ Good
public static final String AGGREGATE_TYPE_USER = "user";
outboxEvent.setAggregateType(AGGREGATE_TYPE_USER);

// ❌ Bad
outboxEvent.setAggregateType("USER");  // 대문자 하드코딩
```

### 2. 테스트 데이터 생성

```bash
# publish-event.sh 스크립트는 이미 소문자 사용
./publish-event.sh
# 선택: 1 (UserCreated) → 토픽: outbox.user
```

### 3. Consumer 설정

```java
@KafkaListener(topics = "outbox.user")  // 소문자 토픽명 사용
public void handleUserEvent(String message) {
    // 처리 로직
}
```

### 4. 문서화

모든 문서와 예제에서 **소문자 토픽명**만 사용:

- README.md
- 아키텍처 다이어그램
- API 문서
- 코드 주석

## 🔍 확인 방법

### 토픽 목록 확인

```bash
./list-outbox-topics.sh
```

### 특정 토픽 이벤트 확인

```bash
./view-outbox-events.sh outbox.user
./view-outbox-events.sh outbox.order
./view-outbox-events.sh outbox.product
```

### 데이터베이스 확인

```bash
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud -e \
  "SELECT aggregate_type, COUNT(*) as count 
   FROM outbox_events 
   GROUP BY aggregate_type;"
```

출력 예시:
```
+----------------+-------+
| aggregate_type | count |
+----------------+-------+
| user           |     2 |
| order          |     2 |
| product        |     1 |
+----------------+-------+
```

## 📚 관련 문서

- [README.md](./README.md) - Outbox Pattern 전체 가이드
- [SCHEMA_VERIFICATION.md](./SCHEMA_VERIFICATION.md) - Java Entity와 DB 스키마 검증
- [Kafka Topic Naming Conventions](https://cnr.sh/essays/how-paint-bike-shed-kafka-topic-naming-conventions)
- [Debezium Outbox Event Router](https://debezium.io/documentation/reference/stable/transformations/outbox-event-router.html)

## 🎉 결론

Outbox Pattern에서는 **소문자 토픽명**을 사용하여:

1. ✅ Kafka 표준 관례 준수
2. ✅ 크로스 플랫폼 호환성 보장
3. ✅ 읽기 쉽고 일관성 있는 명명
4. ✅ 자동화 스크립트 작성 용이

모든 `aggregate_type` 값은 **소문자**로 저장하고, 토픽명도 자동으로 **소문자**로 생성됩니다.
