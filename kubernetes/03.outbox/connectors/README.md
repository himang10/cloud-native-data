# MariaDB Outbox Connector 구성 가이드

Debezium Outbox Event Router를 활용한 MariaDB → Kafka Outbox Pattern 구현 가이드입니다.  
`outbox_events` 테이블의 변경을 감지하여 `aggregate_type`별로 자동 라우팅합니다.

## 📋 목차

- [Outbox Pattern이란?](#outbox-pattern이란)
- [전체 아키텍처](#전체-아키텍처)
- [MariaDB Outbox Connector](#mariadb-outbox-connector)
- [필드별 상세 설명](#필드별-상세-설명)
- [배포 및 운영 가이드](#배포-및-운영-가이드)

---

## Outbox Pattern이란?

### 개념

**Outbox Pattern**은 마이크로서비스에서 **데이터베이스 트랜잭션과 이벤트 발행의 원자성**을 보장하기 위한 패턴입니다.

도메인 데이터 저장과 이벤트 발행을 **동일한 트랜잭션**으로 처리하여 유실 없이 메시지를 전달합니다.

```
┌────────────────────────────────────────────────────────────────┐
│                     Producer (Spring Boot)                     │
│                                                                │
│   ┌──────────────────┐    단일 트랜잭션     ┌─────────────────┐   │
│   │  도메인 테이블      │ ←──────────────── │  outbox_events  │   │
│   │  (users, orders) │                   │  (이벤트 임시      │  │
│   │                  │                   │   저장소)         │  │
│   └──────────────────┘                   └────────┬────────┘  │
└──────────────────────────────────────────────────│────────────┘
                                                    │ Debezium CDC
                                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Kafka Connect (Debezium)                       │
│                                                                 │
│  MariaDB Outbox Connector                                       │
│  └─ EventRouter SMT: aggregate_type으로 토픽 자동 분류              │
│                                                                 │
│     aggregate_type='USER'    →  outbox.user                     │
│     aggregate_type='PRODUCT' →  outbox.product                  │
│     aggregate_type='ORDER'   →  outbox.order                    │
└─────────────────────────────────────────────────────────────────┘
                    │                │              │
                    ▼                ▼              ▼
              outbox.user    outbox.product    outbox.order
                    │                │              │
                    └────────────────┴──────────────┘
                                     │ Consumer 구독
                                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Consumer (Spring Boot)                      │
│                                                                 │
│   onUserEvent()    → CustomerService + UserSummaryService       │
│   onProductEvent() → ProductSummaryService                      │
│   onOrderEvent()   → OrderSummaryService                        │
└─────────────────────────────────────────────────────────────────┘
```

### outbox_events 테이블 구조

```sql
CREATE TABLE outbox_events (
    event_id      VARCHAR(36)  PRIMARY KEY,   -- UUID
    aggregate_type VARCHAR(50) NOT NULL,       -- 라우팅 키 (USER, PRODUCT, ORDER)
    aggregate_id  VARCHAR(36)  NOT NULL,       -- Kafka Message Key
    event_type    VARCHAR(100) NOT NULL,       -- 이벤트 종류 (USER_CREATED 등)
    payload       JSON         NOT NULL,       -- Kafka Message Value
    occurred_at   DATETIME     NOT NULL        -- Kafka Header로 전달
);
```

### Debezium EventRouter가 생성하는 Kafka 메시지 구조

```
┌──────────────────────────────────────────┐
│              Kafka 메시지                  │
│                                          │
│  KEY     = aggregate_id (UUID)           │
│  VALUE   = payload (JSON)                │
│  Headers:                                │
│    event_id       = event_id 컬럼         │
│    event_type     = event_type 컬럼       │
│    aggregate_id   = aggregate_id 컬럼     │
│    aggregate_type = aggregate_type 컬럼   │
│    occurred_at    = occurred_at 컬럼      │
└──────────────────────────────────────────┘
```

---

## 전체 아키텍처

```
MariaDB (cloud.outbox_events)
    │
    │  Binlog CDC (Debezium MySqlConnector)
    ▼
Kafka Connect
    │  EventRouter SMT: ${routedByValue} = aggregate_type 값 (소문자)
    ├──→ outbox.user    (aggregate_type='USER')
    ├──→ outbox.product (aggregate_type='PRODUCT')
    └──→ outbox.order   (aggregate_type='ORDER')
```

---

## MariaDB Outbox Connector

### 역할

MariaDB의 **Binlog를 실시간으로 읽어** `cloud.outbox_events` 테이블에 INSERT된 이벤트를 감지하고,  
**`aggregate_type` 컬럼 값**을 기준으로 Kafka 토픽에 자동 라우팅합니다.

### 파일: `mariadb-outbox-connector.yaml`

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: mariadb-outbox-connector-v1.1
  namespace: kafka
  labels:
    strimzi.io/cluster: debezium-source-connect

spec:
  class: io.debezium.connector.mysql.MySqlConnector
  tasksMax: 1
  
  config:
    # [1] 데이터베이스 연결 설정
    database.hostname: mariadb-1.kafka.svc.cluster.local
    database.port: "3306"
    database.user: skala
    database.password: Skala25a!23$
    database.connectionTimeZone: Asia/Seoul
    connect.timeout.ms: "30000"

    # [2] 데이터베이스 서버 설정
    database.server.id: "284059"
    topic.prefix: mariadb-outbox-source-server

    # [3] Outbox 테이블 캡처 설정
    database.include.list: cloud
    table.include.list: cloud.outbox_events
    include.schema.changes: "false"

    # [4] 스냅샷 설정
    snapshot.mode: initial
    snapshot.locking.mode: minimal

    # [5] 스키마 히스토리 설정
    schema.history.internal.kafka.bootstrap.servers: my-kafka-cluster-kafka-bootstrap:9092
    schema.history.internal.kafka.topic: mariadb.dbhistory.outbox-source-server

    # [6] Outbox Event Router SMT
    transforms: outbox
    transforms.outbox.type: io.debezium.transforms.outbox.EventRouter
    transforms.outbox.table.field.event.id: event_id
    transforms.outbox.table.field.event.key: aggregate_id
    transforms.outbox.table.field.event.type: event_type
    transforms.outbox.table.field.event.payload: payload
    transforms.outbox.table.expand.json.payload: true
    transforms.outbox.route.by.field: aggregate_type
    transforms.outbox.route.topic.replacement: outbox.${routedByValue}
    transforms.outbox.table.fields.additional.placement: event_id:header,event_type:header,aggregate_type:header,aggregate_id:header,occurred_at:header

    # [7] 컨버터 설정
    key.converter: org.apache.kafka.connect.storage.StringConverter
    value.converter: org.apache.kafka.connect.json.JsonConverter
    value.converter.schemas.enable: false

    # [8] 토픽 자동 생성 설정
    topic.creation.enable: "true"
    topic.creation.default.partitions: "3"
    topic.creation.default.replication.factor: "1"

    # [9] 성능 튜닝 설정
    max.batch.size: "2048"
    max.queue.size: "8192"
    poll.interval.ms: "1000"

    # [10] 에러 처리 설정
    errors.tolerance: all
    errors.log.enable: "true"
    errors.log.include.messages: "true"
    errors.deadletterqueue.topic.name: "outbox-connector-errors"
    errors.deadletterqueue.topic.replication.factor: "1"

    # [11] DDL 파싱 에러 해결 설정
    schema.history.internal.skip.unparseable.ddl: "true"
```

---

## 필드별 상세 설명

### [1] 데이터베이스 연결 설정

| 필드 | 설명 | 변경 필요 여부 |
|------|------|---------------|
| `database.hostname` | MariaDB 호스트명 | ✅ **필수** |
| `database.port` | MariaDB 포트 (기본: 3306) | 환경에 따라 |
| `database.user` | CDC 전용 사용자 (REPLICATION 권한 필요) | ✅ **필수** |
| `database.password` | 사용자 비밀번호 | ✅ **필수** |
| `database.connectionTimeZone` | 타임존 설정 | 선택 |
| `connect.timeout.ms` | 연결 타임아웃 (밀리초) | 선택 |

**사용자 권한 요구사항:**
```sql
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'skala'@'%';
FLUSH PRIVILEGES;
```

> **권한 설명**
>
> | 권한 | 설명 |
> |------|------|
> | `SELECT` | 초기 스냅샷 수행 시 테이블 데이터 읽기 |
> | `RELOAD` | 스냅샷 중 `FLUSH TABLES` 실행 |
> | `SHOW DATABASES` | 캡처 대상 DB 탐색 |
> | `REPLICATION SLAVE` | Binlog 스트림 실시간 수신 — CDC의 핵심 |
> | `REPLICATION CLIENT` | `SHOW MASTER STATUS` 등 Binlog 위치 조회 |
>
> Debezium은 실제 Slave DB가 아니지만 **"가짜 Slave"로 접속**하여 Binlog를 가로채 Kafka로 전송합니다.
> ```
> [MariaDB] ──Binlog 스트리밍──→ [Debezium] ──이벤트──→ [Kafka]
>           (Slave인 척 접속)
> ```

---

### [2] 데이터베이스 서버 설정

| 필드 | 설명 | 변경 필요 여부 |
|------|------|---------------|
| `database.server.id` | Binlog 복제용 고유 서버 ID (1~2^32-1) | ✅ **권장** |
| `topic.prefix` | 스키마 히스토리 토픽 등에 사용될 접두사 | 선택 |

**중요:** `database.server.id`는 MariaDB 클러스터 내에서 고유해야 합니다. 랜덤 값 사용 권장.

> **Outbox Connector의 `topic.prefix` 역할**
>
> 일반 CDC Connector와 달리 EventRouter SMT가 토픽을 직접 결정하므로,  
> `topic.prefix`는 **데이터 토픽 이름에 영향을 미치지 않습니다.**  
> 스키마 히스토리 토픽(`mariadb.dbhistory.outbox-source-server`)에만 사용됩니다.

---

### [3] Outbox 테이블 캡처 설정

| 필드 | 설명 | 값 |
|------|------|------|
| `database.include.list` | 캡처할 데이터베이스 | `cloud` |
| `table.include.list` | 캡처할 테이블 — outbox_events 하나만 지정 | `cloud.outbox_events` |
| `include.schema.changes` | DDL 변경사항 캡처 여부 | `false` (권장) |

> **`table.include.list`를 `outbox_events`만 지정하는 이유**
>
> - Outbox Pattern은 `outbox_events` 테이블만 이벤트 버스로 사용
> - `users`, `products` 등 도메인 테이블은 캡처 불필요 (불필요한 부하 방지)
> - 기존 CDC Connector와 **동일한 MariaDB**를 바라봐도 캡처 대상이 달라 충돌 없음

---

### [4] 스냅샷 설정

스냅샷은 Debezium이 최초 시작될 때 현재 DB의 데이터를 전체 읽어 Kafka로 전송하고,  
그 시점의 **Binlog 위치(Position)** 를 `connect-offsets` 토픽에 기준점으로 저장한 뒤  
이후 변경사항(INSERT/UPDATE/DELETE)을 Binlog에서 실시간으로 읽어 이벤트를 전송하는 초기화 방식이다.

| 필드 | 설명 | 옵션 |
|------|------|------|
| `snapshot.mode` | 초기 스냅샷 방식 | `initial`, `schema_only`, `never` |
| `snapshot.locking.mode` | 스냅샷 중 테이블 잠금 방식 | `minimal`, `none`, `extended` |

**snapshot.mode 옵션:**

| 모드 | 동작 | 사용 시기 |
|------|------|----------|
| `initial` | 최초 실행 시 기존 데이터 스냅샷 → Binlog 캡처 | **기본값, 권장** |
| `schema_only` | 스키마만 캡처, 기존 데이터 무시 | 과거 이벤트 재처리 불필요 시 |
| `never` | 스냅샷 없이 현재 Binlog부터 캡처 | 이미 동기화 완료된 경우 |

> **Outbox Pattern에서 `initial` vs `schema_only`**
>
> - `initial`: 기존 `outbox_events` 데이터(아직 처리 안 된 이벤트)도 전송
> - `schema_only`: Connector 시작 이후 새로 INSERT된 이벤트만 전송
>
> 이미 처리된 이벤트가 `outbox_events`에 남아있다면 중복 처리 방지를 위해 `schema_only` 권장.

---

### [5] 스키마 히스토리 설정

**스키마 히스토리**는 테이블 구조(DDL)가 시간에 따라 어떻게 변해왔는지를 Kafka 토픽에 저장해 두는 내부 이력입니다.

Binlog에는 "데이터가 바뀌었다"는 사실만 기록됩니다. 그러나 그 데이터를 정확히 해석하려면 **이벤트가 발생한 당시 테이블의 컬럼 구성**을 알아야 합니다.  
예를 들어 `name` 컬럼만 있던 시점의 Binlog 이벤트와 `email` 컬럼이 추가된 이후의 이벤트는 스키마가 다르므로, Debezium은 스키마 히스토리를 참조하여 각 시점의 row 변경 내용을 올바르게 해석합니다.

> **Debezium의 세 가지 상태 관리 역할**
>
> | 개념 | 저장 위치 | 역할 |
> |------|----------|------|
> | **Offset** | `connect-offsets` 토픽 | Binlog의 어디까지 읽었는지 위치 추적 |
> | **Snapshot** | 없음 (일회성 실행) | 최초 시작 시 현재 DB 데이터 상태를 전체 읽어 Kafka로 전송 |
> | **Schema History** | 별도 Kafka 토픽 | 테이블 구조(DDL)가 시간에 따라 어떻게 변해왔는지 저장 |
>
> Connector를 재시작하면 Offset으로 읽던 위치를 복원하고, Schema History로 그 시점의 스키마를 복원합니다.

| 필드 | 설명 | 필수 |
|------|------|------|
| `schema.history.internal.kafka.bootstrap.servers` | Kafka 브로커 주소 | ✅ **필수** |
| `schema.history.internal.kafka.topic` | DDL 변경 이력 저장 토픽 | ✅ **필수** |
| `schema.history.internal.skip.unparseable.ddl` | 파싱 불가 DDL 무시하고 계속 진행 | 선택 |

```yaml
schema.history.internal.kafka.bootstrap.servers: my-kafka-cluster-kafka-bootstrap:9092
schema.history.internal.kafka.topic: mariadb.dbhistory.outbox-source-server
schema.history.internal.skip.unparseable.ddl: "true"
```

> **기존 CDC Connector와 다른 히스토리 토픽을 사용하는 이유**
>
> 동일한 MariaDB를 바라보더라도 Connector 인스턴스가 다르면  
> **각자 독립적으로 스키마 히스토리를 관리**해야 합니다.  
> 히스토리 토픽을 공유하면 Connector 재시작 시 스키마 충돌이 발생할 수 있습니다.

---

### [6] Outbox Event Router SMT (핵심)

Outbox Pattern의 핵심 설정입니다. **SMT(Single Message Transform)**가 `outbox_events` 테이블의 각 컬럼을 Kafka 메시지 구조로 변환하고 토픽을 결정합니다.

#### 필드 매핑 설정

| 설정 | 역할 | outbox_events 컬럼 |
|------|------|-------------------|
| `table.field.event.id` | 이벤트 고유 ID | `event_id` |
| `table.field.event.key` | Kafka Message **KEY** | `aggregate_id` |
| `table.field.event.type` | 이벤트 종류 | `event_type` |
| `table.field.event.payload` | Kafka Message **VALUE** | `payload` |
| `table.expand.json.payload` | payload JSON 문자열을 JSON 객체로 파싱 | `true` |

```
outbox_events row → Kafka 메시지 변환
┌──────────────────┬───────────────────────────────────────┐
│  event_id        │ → 헤더로 전달                          │
│  aggregate_id    │ → Kafka Message KEY                   │
│  event_type      │ → 헤더로 전달                          │
│  payload (JSON)  │ → Kafka Message VALUE                 │
│  aggregate_type  │ → 토픽명 결정 (${routedByValue})       │
│  occurred_at     │ → 헤더로 전달                          │
└──────────────────┴───────────────────────────────────────┘
```

#### 토픽 라우팅 설정

```yaml
transforms.outbox.route.by.field: aggregate_type
transforms.outbox.route.topic.replacement: outbox.${routedByValue}
```

`${routedByValue}`는 Debezium EventRouter의 **플레이스홀더**로, `route.by.field`에 지정한 컬럼(`aggregate_type`)의 실제 값(자동 소문자 변환)으로 치환됩니다.

| `aggregate_type` 컬럼 값 | `${routedByValue}` | 최종 토픽 |
|---|---|---|
| `USER` | `user` | `outbox.user` |
| `PRODUCT` | `product` | `outbox.product` |
| `ORDER` | `order` | `outbox.order` |

#### 헤더 전달 설정

```yaml
transforms.outbox.table.fields.additional.placement:
  event_id:header,event_type:header,aggregate_type:header,aggregate_id:header,occurred_at:header
```

`outbox_events`의 메타데이터 컬럼들을 **Kafka 메시지 헤더**로 전달합니다.  
Consumer에서는 `@Header("event_id")` 등으로 직접 접근 가능합니다.

> **`expand.json.payload: true` 설정의 중요성**
>
> `false` (기본값): payload가 JSON 문자열로 전송됨
> ```json
> "{\"name\": \"Alice\", \"email\": \"alice@example.com\"}"
> ```
> `true`: payload가 실제 JSON 객체로 파싱되어 전송됨
> ```json
> {"name": "Alice", "email": "alice@example.com"}
> ```
> Consumer에서 `objectMapper.readTree(message)`로 바로 파싱 가능합니다.

---

### [7] 컨버터 설정

| 필드 | 설명 | 값 |
|------|------|------|
| `key.converter` | Message Key 직렬화 방식 | `StringConverter` |
| `value.converter` | Message Value 직렬화 방식 | `JsonConverter` |
| `value.converter.schemas.enable` | Kafka Schema Registry 스키마 포함 여부 | `false` |

```yaml
key.converter: org.apache.kafka.connect.storage.StringConverter
value.converter: org.apache.kafka.connect.json.JsonConverter
value.converter.schemas.enable: false
```

> **`schemas.enable: false`로 설정하는 이유**
>
> `true`이면 메시지에 **스키마 정보가 포함**되어 Consumer가 스키마를 알 수 있지만,  
> 메시지 크기가 커지고 Schema Registry 의존성이 생깁니다.  
> Outbox Pattern에서는 `payload` 필드 자체가 이미 도메인 스키마를 포함하므로 `false` 권장.

---

### [8] 토픽 자동 생성 설정

| 필드 | 설명 | 값 |
|------|------|------|
| `topic.creation.enable` | Connector가 토픽 자동 생성 여부 | `true` |
| `topic.creation.default.partitions` | 자동 생성 토픽의 파티션 수 | `3` |
| `topic.creation.default.replication.factor` | 복제 계수 | `1` |

> **파티션 수 3 권장 이유**
>
> Consumer(`outbox-consumer`) 설정에서 `concurrency: 3`으로 3개의 리스너 스레드를 사용합니다.  
> **파티션 수 = Consumer 스레드 수**일 때 최대 병렬 처리가 가능합니다.
>
> ```
> outbox.user (파티션 3개)
>   파티션 0 ──→ Consumer 스레드 1
>   파티션 1 ──→ Consumer 스레드 2
>   파티션 2 ──→ Consumer 스레드 3
> ```

---

### [9] 성능 튜닝 설정

| 필드 | 설명 | 권장값 |
|------|------|--------|
| `max.batch.size` | 내부 큐에서 한 번에 처리할 최대 이벤트 수 | `2048` |
| `max.queue.size` | Binlog 이벤트를 임시 저장하는 내부 큐 크기 | `8192` |
| `poll.interval.ms` | 큐에서 이벤트를 꺼내 Kafka로 전송하는 주기 (ms) | `1000` |

```
MariaDB Binlog
     ↓ 실시간 스트리밍
[내부 큐] ── 최대 max.queue.size(8192)개 대기
     ↓ poll.interval.ms(1000ms) 마다
[배치 처리] ── 한 번에 최대 max.batch.size(2048)개 묶음
     ↓
Kafka Topic (outbox.user / outbox.product / outbox.order)
```

**규칙:** `max.batch.size` < `max.queue.size` 이어야 합니다.

---

### [10] 에러 처리 설정

| 필드 | 설명 | 옵션 |
|------|------|------|
| `errors.tolerance` | 에러 허용 수준 | `none` (중단), `all` (무시) |
| `errors.log.enable` | 에러 로깅 활성화 | `true` (권장) |
| `errors.log.include.messages` | 에러 메시지 상세 포함 | `true` (권장) |
| `errors.deadletterqueue.topic.name` | 처리 실패한 메시지를 보관할 DLQ 토픽 | `outbox-connector-errors` |

**권장 설정:**
- **운영 환경**: `errors.tolerance: none` — 문제 발생 시 즉시 중단하여 데이터 무결성 보장
- **개발/테스트**: `errors.tolerance: all` — 에러를 DLQ로 보내고 계속 진행

---

### [11] DDL 파싱 에러 해결 설정

```yaml
schema.history.internal.skip.unparseable.ddl: "true"
```

Debezium이 파싱할 수 없는 DDL 구문을 만났을 때 에러 없이 무시하고 계속 진행합니다.  
MariaDB와 MySQL의 문법 차이로 발생하는 파싱 오류를 방지합니다.

---

## 배포 및 운영 가이드

### 배포

```bash
# Connector 배포
kubectl apply -f connectors/mariadb-outbox-connector.yaml -n kafka

# 상태 확인
kubectl get kafkaconnector -n kafka
kubectl describe kafkaconnector mariadb-outbox-connector-v1.1 -n kafka
```

### 토픽 생성 확인

```bash
# Kafka 클라이언트 Pod 접속
kubectl exec -it kafka-client -n kafka -- bash

# 생성된 토픽 목록 확인
kafka-topics.sh --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092 --list | grep outbox

# 기대 결과
outbox.user
outbox.product
outbox.order
outbox-connector-errors          # DLQ 토픽
mariadb.dbhistory.outbox-source-server  # 스키마 히스토리 토픽
```

### 이벤트 흐름 확인

```bash
# outbox.user 토픽 메시지 확인
kafka-console-consumer.sh \
  --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092 \
  --topic outbox.user \
  --from-beginning \
  --property print.headers=true \
  --property print.key=true
```

출력 예시:
```
Headers: event_id:uuid-1234,event_type:USER_CREATED,aggregate_type:user,...
Key: user-uuid-5678
Value: {"name":"Alice","email":"alice@example.com","role":"USER"}
```

### Connector 재시작 (문제 발생 시)

```bash
# Connector 삭제 후 재배포
kubectl delete kafkaconnector mariadb-outbox-connector-v1.1 -n kafka
kubectl apply -f connectors/mariadb-outbox-connector.yaml -n kafka
```

### 주의사항

| 항목 | 내용 |
|------|------|
| `database.server.id` | MariaDB 클러스터 내 고유해야 함. 기존 CDC Connector와 다른 값 사용 |
| `table.include.list` | `outbox_events`만 지정. 도메인 테이블 추가하면 EventRouter가 오동작 |
| `aggregate_type` 값 | 대/소문자 관계없이 자동 소문자 변환되어 토픽명 결정 |
| `snapshot.mode` | 기존 미처리 이벤트가 있으면 `initial`, 없으면 `schema_only` 권장 |
