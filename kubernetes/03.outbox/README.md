# Outbox Pattern 실습 프로젝트

> 개념 이해 → [WHAT.md](WHAT.md)  
> 단계별 실행 절차 → [TEST-GUIDE.md](TEST-GUIDE.md)

---

## 1. 실습 목표

이 실습은 마이크로서비스 환경에서 **트랜잭션 보장**과 **이벤트 발행**을 동시에 처리하는  
Outbox Pattern을 Spring Boot + MariaDB + Debezium + Kafka 스택으로 직접 구현하고 검증합니다.

| 학습 항목 | 내용 |
|-----------|------|
| Outbox Pattern 구현 | Spring Boot에서 @Transactional 내에 이벤트 저장 방법 |
| Debezium EventRouter | aggregate_type 기반 토픽 라우팅 SMT 설정 |
| Consumer 이벤트 처리 | KafkaListener로 이벤트 수신 및 PostgreSQL에 저장 |
| 전체 파이프라인 검증 | Producer API 호출 → Kafka → Consumer → PostgreSQL 확인 |

---

## 2. 전체 시스템 구성

```
[Producer API] ──(HTTP)──→ [MariaDB: users + outbox_events]
                                       │
                                    [Debezium Outbox Connector]
                                    EventRouter SMT로 라우팅
                                       │
                          ┌────────────┴──────────────────────────┐
                          │                                       │
                       outbox.user                  outbox.order / outbox.product
                          │
                    [Consumer API]
                    @KafkaListener
                          │
                    [PostgreSQL: user_summary, order_summary, product_summary]
```

---

## 3. 프로젝트 디렉토리 구성

```
03.outbox/
├── WHAT.md                          # Outbox Pattern 개념 설명
├── README.md                        # 이 파일
├── TEST-GUIDE.md                    # 실습 실행 절차
│
├── producer/                        # Spring Boot Producer 서비스
│   ├── src/main/java/.../
│   │   ├── controller/              # REST API (UserController, OrderController 등)
│   │   ├── service/                 # 비즈니스 로직 (UserService, OutboxService 등)
│   │   ├── domain/                  # 엔티티 (User, Order, Product, OutboxEvent)
│   │   └── repository/              # JPA Repository
│   └── pom.xml
│
├── consumer/                        # Spring Boot Consumer 서비스
│   ├── src/main/java/.../
│   │   ├── listener/                # OutboxEventListener (KafkaListener)
│   │   ├── service/                 # UserSummaryService, OrderSummaryService 등
│   │   ├── domain/                  # UserSummary, OrderSummary, ProductSummary
│   │   └── repository/              # JPA Repository
│   └── pom.xml
│
├── connectors/
│   └── mariadb-outbox-connector.yaml  # Debezium Outbox KafkaConnector
│
├── k8s/
│   ├── producer-deployment.yaml     # Producer Kubernetes 배포 설정
│   ├── producer-service.yaml        # Producer Service (LoadBalancer)
│   ├── consumer-deployment.yaml     # Consumer Kubernetes 배포 설정
│   └── consumer-service.yaml        # Consumer Service
│
├── script/
│   ├── test-00-create-outbox-event.sh  # outbox_events 테이블 생성
│   ├── test-01-insert-outbox-event.sh  # 테스트 이벤트 직접 삽입 (DB 접근)
│   ├── test-02-check-kafka-topic.sh    # Kafka Topic 메시지 확인
│   └── test-03-test-consumer.sh        # Consumer API 응답 확인
│
└── sql/
    ├── 01-create-outbox-table.sql   # outbox_events 테이블 DDL
    └── 02-insert-sample-data.sql    # 샘플 데이터
```

---

## 4. 구성 요소별 역할

### 4.1 Producer (Spring Boot)

`UserService`, `OrderService`, `ProductService`에서 도메인 객체를 저장할 때  
`OutboxService.publishEvent()`를 호출하여 `outbox_events` 테이블에 이벤트를 함께 저장합니다.

```java
@Transactional
public User createUser(User user) {
    User savedUser = userRepository.save(user);  // users 테이블 저장

    outboxService.publishEvent(           // outbox_events 테이블 저장
        savedUser.getId(),
        "user",           // aggregate_type → outbox.user 토픽
        "CREATED",        // event_type
        savedUser         // payload
    );
    return savedUser;
}
```

두 저장 작업이 동일한 `@Transactional` 안에 있으므로 하나라도 실패하면 모두 롤백됩니다.

### 4.2 Debezium Outbox Connector (mariadb-outbox-connector.yaml)

`outbox_events` 테이블만 감시하며, **EventRouter SMT**로 `aggregate_type` 값에 따라 Topic을 결정합니다.

| 설정 | 값 | 설명 |
|------|----|------|
| `table.include.list` | `cloud.outbox_events` | outbox_events 테이블만 캡처 |
| `transforms.outbox.type` | `EventRouter` | Outbox 전용 SMT |
| `route.by.field` | `aggregate_type` | 라우팅 기준 필드 |
| `route.topic.replacement` | `outbox.${routedByValue}` | Topic 이름 결정 규칙 |

**생성되는 Kafka Topic:**
```
outbox.user
outbox.order
outbox.product
```

### 4.3 Consumer (Spring Boot)

`OutboxEventListener`가 각 Topic을 `@KafkaListener`로 구독하여,  
수신된 이벤트를 PostgreSQL의 `*_summary` 테이블에 저장합니다.

```java
@KafkaListener(topics = "outbox.user", groupId = "outbox-consumer-group")
public void onUserEvent(@Payload String message, @Header("event_id") String eventId, ...) {
    userSummaryService.processUserEvent(eventId, eventType, occurredAt, payload);
    // event_id로 중복 처리 방지 (멱등성)
}
```

### 4.4 Kubernetes 배포

Producer와 Consumer 모두 Kubernetes에 배포됩니다.  
`producer-deployment.yaml`에는 MariaDB 연결 정보,  
`consumer-deployment.yaml`에는 Kafka 및 PostgreSQL 연결 정보가 환경변수로 설정됩니다.

---

## 5. 실습을 통해 확인할 수 있는 것

1. Producer API로 사용자를 생성하면 `users` 테이블과 `outbox_events` 테이블에 동시에 저장된다.
2. Debezium이 `outbox_events`의 변경을 감지하여 `outbox.user` Topic으로 이벤트를 전송한다.
3. Consumer가 `outbox.user`를 구독하여 PostgreSQL `user_summary`에 데이터를 저장한다.
4. Kafka를 통해 이벤트가 전달되므로 Producer와 Consumer는 서로 독립적으로 동작한다.
5. `event_id(UUID)` 기반 멱등성 처리로 중복 이벤트가 수신되어도 한 번만 처리된다.
