# Outbox Pattern이란 무엇인가

## 1. 배경: 마이크로서비스의 이중 쓰기 문제

마이크로서비스 환경에서 비즈니스 로직은 보통 두 가지 작업을 함께 수행합니다.

```
사용자 생성 API 호출
    → 1) DB에 사용자 데이터 저장
    → 2) Kafka에 "사용자 생성됨" 이벤트 발행
```

이 두 작업을 단순히 순서대로 실행하면 심각한 문제가 생깁니다.

```
시나리오 A: DB 저장 성공 → Kafka 발행 실패
  결과: DB에는 데이터가 있지만, 다른 서비스는 이벤트를 받지 못함
  → 데이터 불일치

시나리오 B: Kafka 발행 성공 → DB 저장 실패 (트랜잭션 롤백)
  결과: 이벤트는 이미 전송됐지만 데이터는 없음
  → 유령 이벤트 발생
```

이 문제를 **이중 쓰기(Dual Write) 문제**라고 합니다.  
Outbox Pattern은 이 문제를 **단일 DB 트랜잭션**으로 해결합니다.

---

## 2. Outbox Pattern의 핵심 아이디어

```
[해결책]
사용자 생성 API 호출
    → 단일 트랜잭션으로:
        1) users 테이블에 사용자 저장
        2) outbox_events 테이블에 이벤트 저장 ← 같은 트랜잭션!
    
    → Debezium이 outbox_events의 변경을 감지
    → Kafka Topic으로 자동 전송
```

핵심은 **애플리케이션이 Kafka에 직접 쓰지 않는다**는 것입니다.  
애플리케이션은 자신의 DB에만 씁니다. Kafka 전송은 Debezium이 담당합니다.

---

## 3. 전체 처리 흐름

```
Producer API  (Spring Boot 애플리케이션, 사용자 생성)
    │ @Transactional
    ├─→ users 테이블 저장        ┐ 같은 트랜잭션
    └─→ outbox_events 테이블 저장 ┘

MariaDB (outbox_events)  ← Debezium이 Binlog 감시
    │ CDC (Binlog 읽기)
    ▼
Debezium Outbox Connector  (Outbox Event Router SMT 적용)
    ├─→ outbox.user    (aggregate_type='user')
    ├─→ outbox.order   (aggregate_type='order')
    └─→ outbox.product (aggregate_type='product')

Consumer API  (Spring Boot, @KafkaListener)
    │
    ▼
PostgreSQL  (user_summary, order_summary 테이블)
```

---

## 4. 핵심 개념 설명

### 4.1 outbox_events 테이블

Outbox Pattern의 핵심 테이블입니다. 발행할 이벤트를 임시로 저장합니다.

```sql
CREATE TABLE outbox_events (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id        CHAR(36) NOT NULL UNIQUE,    -- UUID (멱등성 보장)
    aggregate_id    BIGINT NOT NULL,              -- 이벤트 대상 ID (user.id 등)
    aggregate_type  VARCHAR(255) NOT NULL,        -- 토픽 라우팅 키 ('user', 'order', 'product')
    event_type      VARCHAR(255) NOT NULL,        -- 이벤트 종류 ('CREATED', 'UPDATED', 'DELETED')
    payload         JSON NOT NULL,               -- 이벤트 상세 데이터
    occurred_at     TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    processed       TINYINT(1) NOT NULL DEFAULT 0
);
```

| 컬럼 | 역할 |
|------|------|
| `event_id` | UUID로 중복 이벤트 방지 (멱등성) |
| `aggregate_type` | Debezium이 이 값으로 Kafka Topic을 결정 |
| `payload` | Consumer가 처리할 이벤트 데이터 (JSON) |
| `processed` | 처리 완료 여부 플래그 (모니터링용) |

### 4.2 Outbox Event Router (Debezium SMT)

일반 Debezium CDC는 테이블 이름 기반으로 Topic을 생성합니다.  
Outbox Pattern에서는 **Outbox Event Router** SMT(Single Message Transform)를 사용하여  
`aggregate_type` 필드 값에 따라 다른 Topic으로 라우팅합니다.

```yaml
transforms: outbox
transforms.outbox.type: io.debezium.transforms.outbox.EventRouter
transforms.outbox.route.by.field: aggregate_type
transforms.outbox.route.topic.replacement: outbox.${routedByValue}
```

```
outbox_events (aggregate_type='user')    → Kafka Topic: outbox.user
outbox_events (aggregate_type='order')   → Kafka Topic: outbox.order
outbox_events (aggregate_type='product') → Kafka Topic: outbox.product
```

### 4.3 멱등성(Idempotency)

네트워크 장애로 같은 메시지가 여러 번 전달될 수 있습니다(At-Least-Once).  
Consumer는 `event_id(UUID)`를 확인하여 이미 처리한 이벤트를 무시합니다.

```
이벤트 수신
    → event_id가 이미 처리된 것이라면 → 무시 (중복)
    → 처음 받은 event_id라면 → 정상 처리
```

### 4.4 이 실습과 일반 CDC 실습의 차이

| 항목 | 02.cdc (일반 CDC) | 03.outbox (Outbox Pattern) |
|------|-------------------|---------------------------|
| 감시 대상 | 도메인 테이블 직접 (users, orders) | outbox_events 테이블만 |
| Topic 생성 | 테이블명 기반 | aggregate_type 기반 |
| 트랜잭션 보장 | DB 저장만 보장 | DB 저장 + 이벤트 발행 동시 보장 |
| 애플리케이션 코드 | 기존 코드 수정 불필요 | outbox_events 저장 코드 추가 필요 |
| 적합한 상황 | 레거시 DB 동기화 | 이벤트 기반 마이크로서비스 |

---

## 5. 왜 Outbox Pattern이 필요한가

단순히 Kafka에 직접 발행하거나 CDC만 사용하면 되지 않냐는 의문이 생길 수 있습니다.

```
직접 Kafka 발행:
  - DB 저장과 Kafka 발행 사이에 트랜잭션 보장 불가
  - DB 롤백 후에도 Kafka 메시지가 이미 전송될 수 있음

일반 CDC (도메인 테이블 직접 감시):
  - 모든 컬럼 변경이 다 이벤트로 전송됨 (내부 구현 노출)
  - 이벤트 의미(created/updated/deleted)를 표현하기 어려움
  - 멱등성 키(event_id) 관리가 복잡함

Outbox Pattern:
  - 단일 트랜잭션으로 데이터와 이벤트 발행 동시 보장
  - 이벤트 의미와 payload를 명시적으로 설계
  - event_id로 멱등성 처리가 단순해짐
```

> 프로젝트 구성 확인 → [README.md](README.md)  
> 단계별 실행 절차 → [TEST-GUIDE.md](TEST-GUIDE.md)
