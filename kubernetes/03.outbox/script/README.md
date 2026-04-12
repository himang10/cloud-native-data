# Outbox Pattern 테스트 스크립트

이 디렉토리는 Outbox Pattern의 전체 흐름을 단계별로 테스트하는 스크립트를 포함합니다.

---

## 스크립트 목록

| 스크립트 | 설명 | 사용법 |
|---------|------|--------|
| `test-00-create-outbox-event.sh` | MariaDB `outbox_events` 테이블 생성 | `./test-00-create-outbox-event.sh` |
| `test-01-insert-outbox-event.sh` | Outbox 테스트 이벤트 삽입 | `./test-01-insert-outbox-event.sh` |
| `test-02-check-kafka-topic.sh` | Kafka 토픽 메시지 확인 | `./test-02-check-kafka-topic.sh` |
| `test-03-test-consumer.sh` | Consumer 애플리케이션 테스트 | `./test-03-test-consumer.sh` |
| `fix-connector-ddl-error.sh` | DDL 파싱 에러 해결 (트러블슈팅) | `./fix-connector-ddl-error.sh` |

---

## 환경 정보

| 항목 | 값 |
|------|-----|
| MariaDB Namespace | `mariadb` |
| MariaDB Pod | `mariadb-1-0` |
| MariaDB Container | `mariadb` |
| MariaDB 바이너리 | `/opt/bitnami/mariadb/bin/mariadb` |
| MariaDB 사용자 | `skala` / `Skala25a!23$` |
| MariaDB Database | `cloud` |
| Kafka Namespace | `kafka` |
| Kafka Cluster | `my-kafka-cluster` |
| Outbox Kafka 토픽 | `outbox.user` |
| Debezium Connect 클러스터 | `debezium-source-connect` |
| Consumer App Label | `app=outbox-consumer` |
| Consumer Group | `outbox-consumer-group` |

---

## 단계별 테스트

```bash
# 0단계: outbox_events 테이블이 없으면 생성 (최초 1회)
./test-00-create-outbox-event.sh

# 1단계: 테스트 이벤트 삽입
./test-01-insert-outbox-event.sh

# 2단계: Kafka 토픽 메시지 확인 (5~10초 대기 권장)
sleep 10
./test-02-check-kafka-topic.sh

# 3단계: Consumer 확인
./test-03-test-consumer.sh
```

---

## 테스트 흐름

```
┌─────────────────────────────────────────────────────────────┐
                     Outbox Pattern 흐름                      
└─────────────────────────────────────────────────────────────┘

  0️⃣  outbox_events 테이블 생성 (최초 1회)
      └─ test-00-create-outbox-event.sh
          ↓
  1️⃣  MariaDB에 Outbox Event 삽입
      └─ test-01-insert-outbox-event.sh
          ↓
      [MariaDB: cloud.outbox_events]
          ↓
      [Debezium CDC - Binlog 감지]
          ↓
  2️⃣  Kafka 토픽에 메시지 발행
      └─ test-02-check-kafka-topic.sh
          ↓
      [Kafka Topic: outbox.user]
          ↓
  3️⃣  Consumer가 메시지 수신
      └─ test-03-test-consumer.sh
          ↓
      [outbox-consumer Pod (namespace: kafka)]
```

---

## 각 스크립트 상세

### test-00-create-outbox-event.sh

**기능:**
- MariaDB `cloud.outbox_events` 테이블 생성 (Debezium 3.2.3 EventRouter 호환)
- `occurred_at` 컬럼을 `TIMESTAMP(3)` 타입으로 생성 (Debezium 호환 필수)
- 기존 테이블이 있으면 백업 후 재생성
- 테이블 생성 확인 및 테스트 데이터 자동 삽입

**생성되는 테이블 구조:**
```sql
CREATE TABLE outbox_events (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id        CHAR(36) NOT NULL,        -- UUID
    aggregate_id    BIGINT NOT NULL,           -- 집합체 식별자
    aggregate_type  VARCHAR(255) NOT NULL,     -- Kafka 토픽 라우팅 기준
    event_type      VARCHAR(255) NOT NULL,     -- CREATE / UPDATE / DELETE 등
    payload         JSON NOT NULL,             -- 이벤트 페이로드
    occurred_at     TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),  -- Debezium 호환
    processed       TINYINT(1) NOT NULL DEFAULT 0
);
```

**출력 예시:**
```
 MariaDB Pod 확인 완료
  테이블 생성 중...
 outbox_events 테이블 생성 완료!
 Test Event ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

---

### test-01-insert-outbox-event.sh

**기능:**
- MariaDB `cloud.outbox_events` 테이블에 테스트 이벤트 삽입
- `uuidgen`으로 UUID 자동 생성
- `aggregate_type: user` → Kafka 토픽 `outbox.user`로 라우팅
- 삽입된 이벤트 즉시 조회 및 출력

**삽입되는 데이터:**
```sql
INSERT INTO outbox_events (
    event_id,           -- UUID (자동 생성)
    aggregate_id,       -- Unix timestamp
    aggregate_type,     -- 'user'  ← Kafka 토픽: outbox.user
    event_type,         -- 'CREATED'
    payload,            -- {"id":..., "name":"테스트사용자-HHMMSS", "email":...}
    occurred_at,        -- 현재 시간 (TIMESTAMP)
    processed           -- 0
)
```

**출력 예시:**
```
 MariaDB Pod 발견
 Outbox Event 삽입 성공!
 Event ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
 예상 Kafka 토픽: outbox.user
```

---

### test-02-check-kafka-topic.sh

**기능:**
- Kafka 클러스터 상태 확인
- `outbox.user` 토픽 존재 여부 확인
- 토픽 상세 정보 및 최근 메시지 3개 조회
- CloudEvents 형식 여부 자동 판별 (specversion / id / source / type 필드 확인)

**확인 단계:**
1. Kafka 클러스터(`my-kafka-cluster`) Ready 확인
2. Outbox 관련 토픽 목록 조회
3. `outbox.user` 토픽 존재 확인
4. 토픽 파티션/복제 상세 정보
5. 최근 메시지 3개 조회 (헤더·타임스탬프·키 포함)
6. CloudEvents 형식 여부 분석

**출력 예시:**
```
 Kafka 클러스터 정상 동작 중
 토픽 'outbox.user'이 존재합니다
 최근 메시지 (최대 3개):
 CreateTime:... key=12345 value={"specversion":"1.0", ...}
 CloudEvents 형식입니다!
```

**주의사항:**
- Connector가 `mariadb-outbox-cloudevents-connector`면 CloudEvents 형식
- `mariadb-outbox-connector`이면 기본 Outbox 형식

---

### test-03-test-consumer.sh

**기능:**
- `outbox-consumer` Pod 상태 확인
- Consumer 애플리케이션 로그 조회 (최근 50줄)
- Kafka 연결 로그 필터링
- USER 이벤트 처리 로그 확인
- 에러 로그 감지
- Consumer Group(`outbox-consumer-group`) 오프셋 상태 확인

**Consumer Pod가 없는 경우:**
- Kafka console consumer로 `outbox.user` 토픽 메시지를 직접 조회 (최대 5개)

**출력 예시:**
```
 Consumer Pod 발견: outbox-consumer-xxxxxx
 Pod가 Running 상태입니다
 USER 이벤트 처리 로그 발견:
 Received event: event_id=xxxx, user=테스트사용자-xxxxxx
 에러 로그 없음
```

---

### fix-connector-ddl-error.sh (트러블슈팅)

**기능:**
- Debezium Connector에서 DDL 파싱 에러가 발생했을 때 복구
- 기존 Connector 삭제 후 재배포
- DDL 에러 허용 설정(`errors.tolerance: all`) 적용

**사용 시점:**
- Connector 로그에 `DDL statement couldn't be parsed` 에러 발생 시
- Connector Task가 FAILED 상태이고 DDL 관련 에러 메시지가 확인될 때

**실행 방법:**
```bash
./fix-connector-ddl-error.sh
```

---

## 🔍 문제 해결

### Connector가 Ready 상태가 아닌 경우

```bash
# KafkaConnect 상태 확인
kubectl get kafkaconnect debezium-source-connect -n kafka

# Connector 상태 확인
kubectl get kafkaconnector mariadb-outbox-cloudevents-connector -n kafka -o yaml

# KafkaConnect 로그 확인
kubectl logs -n kafka -l strimzi.io/cluster=debezium-source-connect --tail=50
```

### 토픽이 생성되지 않은 경우

**원인:**
- Connector가 아직 이벤트를 처리하지 않음
- MariaDB Binlog가 비활성화되어 있음
- Connector 설정 오류

**확인:**
```bash
# MariaDB Binlog 상태 확인
kubectl exec -n mariadb mariadb-1-0 -c mariadb -- \
  /opt/bitnami/mariadb/bin/mariadb -u skala -pSkala25a\!23\$ cloud \
  -e "SHOW VARIABLES LIKE 'log_bin';"

# Connector 로그 확인
kubectl logs -n kafka -l strimzi.io/cluster=debezium-source-connect --tail=100
```

### Consumer가 메시지를 받지 못하는 경우

**확인:**
```bash
# Consumer Pod 상태
kubectl get pods -n kafka -l app=outbox-consumer

# Consumer 로그 (에러 확인)
kubectl logs -n kafka -l app=outbox-consumer | grep -i error

# Kafka Consumer Group 오프셋 확인
kubectl run kafka-client --rm -i --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  --namespace=kafka \
  -- /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092 \
  --describe \
  --group outbox-consumer-group
```

### DDL 파싱 에러 발생 시

```bash
./fix-connector-ddl-error.sh
```

---

##  성공 기준

-  `cloud.outbox_events` 테이블 존재 (TIMESTAMP(3) 타입)
-  Connector `READY: True` 상태
-  MariaDB에 outbox event 삽입 성공
-  Kafka `outbox.user` 토픽에 메시지 존재
-  Consumer 로그에 이벤트 처리 기록

---

## 실시간 모니터링

**Connector 모니터링:**
```bash
kubectl get kafkaconnector mariadb-outbox-cloudevents-connector -n kafka -w
```

**Kafka 메시지 실시간 확인:**
```bash
kubectl run kafka-consumer --rm -i --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  --namespace=kafka \
  -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092 \
  --topic outbox.user \
  --from-beginning \
  --property print.headers=true \
  --property print.timestamp=true \
  --property print.key=true
```

**Consumer 로그 실시간 확인:**
```bash
kubectl logs -n kafka -f -l app=outbox-consumer
```

**MariaDB outbox_events 직접 확인:**
```bash
kubectl exec -n mariadb mariadb-1-0 -c mariadb -- \
  /opt/bitnami/mariadb/bin/mariadb -u skala -pSkala25a\!23\$ cloud \
  -e "SELECT id, event_id, aggregate_type, event_type, occurred_at, processed FROM outbox_events ORDER BY occurred_at DESC LIMIT 10;"
```

