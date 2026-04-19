# Outbox Pattern 실습 실행 가이드

> 개념 이해 → [WHAT.md](WHAT.md)  
> 프로젝트 구성 이해 → [README.md](README.md)

---

## 사전 준비 사항

### 1. 인프라 상태 확인

```bash
# Kafka 클러스터 확인
kubectl get kafka -n kafka

# KafkaConnect 클러스터 확인
kubectl get kafkaconnect -n kafka

# 전체 Pod 상태 확인
kubectl get pods -n kafka
kubectl get pods -n mariadb
kubectl get pods -n postgres
```

**정상 출력 예시:**
```
# Kafka
NAME                                        READY   STATUS    RESTARTS
debezium-source-connect-connect-xxx         1/1     Running   0
my-kafka-cluster-kafka-0                    1/1     Running   0
my-kafka-cluster-zookeeper-0                1/1     Running   0

# MariaDB (mariadb 네임스페이스)
NAME          READY   STATUS    RESTARTS
mariadb-1-0   1/1     Running   0

# PostgreSQL (postgres 네임스페이스)
NAME                          READY   STATUS
postgres-1-postgresql-0       1/1     Running
```

### 2. MariaDB Binlog 설정 확인

```bash
# 02.cdc 제공 스크립트 활용
chmod +x ../02.cdc/script/check-binlog-status.sh
../02.cdc/script/check-binlog-status.sh
```

`log_bin = ON`, `binlog_format = ROW` 가 확인되어야 합니다.

---

## Step 1. outbox_events 테이블 생성

```bash
cd 03.outbox
chmod +x script/00.create-outbox-event.sh
./script/00.create-outbox-event.sh
```

스크립트가 수행하는 작업:
1. 기존 `outbox_events` 테이블이 있으면 `outbox_events_bak`으로 백업
2. `outbox_events` 테이블 새로 생성
3. 테이블 구조 출력으로 확인

**정상 출력:**
```
=== Outbox Events 테이블 생성 ===
...
테이블 생성 완료!

=== 테이블 구조 확인 ===
+----------------+--------------+------+-----+-------------------+
| Field          | Type         | Null | Key | Default           |
+----------------+--------------+------+-----+-------------------+
| id             | bigint(20)   | NO   | PRI | NULL              |
| event_id       | char(36)     | NO   | UNI | NULL              |
| aggregate_id   | bigint(20)   | NO   |     | NULL              |
| aggregate_type | varchar(255) | NO   | MUL | NULL              |
| event_type     | varchar(255) | NO   |     | NULL              |
| payload        | longtext     | NO   |     | NULL              |
| occurred_at    | datetime(3)  | YES  |     | CURRENT_TIMESTAMP |
| processed      | tinyint(1)   | NO   |     | 0                 |
+----------------+--------------+------+-----+-------------------+
```

---

## Step 2. Outbox Connector 배포

```bash
cd 03.outbox

# Connector 배포
kubectl apply -f connectors/mariadb-outbox-connector.yaml

# 상태 확인
kubectl get kafkaconnector -n kafka
```

**예상 출력:**
```
NAME                            CLUSTER                   READY
mariadb-outbox-connector-v1.1   debezium-source-connect   True
```

> `READY = False` 인 경우:
> ```bash
> kubectl describe kafkaconnector mariadb-outbox-connector-v1.1 -n kafka
> kubectl logs -n kafka deployment/debezium-source-connect-connect --tail=100
> ```

**확인 포인트:**
- `table.include.list`가 `cloud.outbox_events`를 정확히 지정하고 있는지 확인
- `strimzi.io/cluster: debezium-source-connect` 레이블이 올바른지 확인

---

## Step 3. 스크립트 기반 Outbox 이벤트 생성·소비 테스트

Producer/Consumer 애플리케이션 배포 전에, 스크립트로 직접 이벤트를 삽입하여 Connector → Kafka → Consumer 흐름이 정상인지 먼저 검증합니다.

### 3-1. Outbox 이벤트 삽입

**단건 실행:**
```bash
cd 03.outbox
chmod +x script/01.insert-outbox-event.sh
./script/01.insert-outbox-event.sh
```

**여러 건 연속 실행 (예: 3건):**
```bash
for i in $(seq 1 3); do
  ./script/01.insert-outbox-event.sh
  sleep 1
done
```

스크립트 동작:
1. `uuidgen`으로 고유한 `event_id` 생성
2. `aggregate_type='user'`, `event_type='CREATED'` 이벤트를 `outbox_events`에 삽입
3. 삽입된 이벤트 내용 출력

**예상 출력:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MariaDB Outbox Event 삽입 테스트 (TIMESTAMP 타입)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Event ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
Aggregate Type: user (→ 토픽: outbox.user)
Timestamp: 2026-04-12 10:00:00

Outbox Event 삽입 성공!
예상 Kafka 토픽: outbox.user
```

> 삽입 후 Debezium이 Binlog를 읽기까지 **5~10초** 대기합니다.

---

### 3-2. Kafka Topic 메시지 확인

Debezium이 이벤트를 감지하여 `outbox.user` 토픽에 발행했는지 확인합니다.

```bash
chmod +x script/02.check-kafka-topic.sh
./script/02.check-kafka-topic.sh
```
**Conduktor UI를 통해 내용을 확인할 수 있습니다.**

**예상 출력:**
```
단계 2: Outbox 관련 토픽 목록 확인
outbox.user

단계 3: outbox.user 토픽 존재 확인
토픽 확인 완료

단계 4: 메시지 확인
event_id:a1b2c3d4-...,event_type:CREATED,aggregate_type:user
{"id":1726050000,"name":"테스트사용자-100000","email":"test-100000@example.com"}
```

**확인 포인트:**
- `outbox.user` 토픽이 목록에 있는지 확인
- 메시지 헤더에 `event_id`, `event_type`, `aggregate_type` 포함 여부 확인

---

### 3-3. Consumer 처리 확인

Consumer 앱이 없는 상태에서 Kafka Console Consumer로 메시지 소비를 직접 확인합니다.

```bash
chmod +x script/03.test-consumer.sh
./script/03.test-consumer.sh
```

Consumer 앱이 배포되지 않은 경우 스크립트가 자동으로 Kafka Console Consumer로 전환하여 `outbox.user` 토픽의 메시지를 출력합니다.

**예상 출력 (Consumer 앱 미배포 시):**
```
Consumer Pod를 찾을 수 없습니다.
대신 Kafka Consumer로 직접 메시지 확인:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Kafka Consumer로 메시지 확인
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{"id":1726050000,"name":"테스트사용자-100000",...}
```

> Step 3까지 완료되면 Connector → Kafka 파이프라인이 정상임을 확인한 것입니다.  
> 이후 Step 4~5에서 Producer/Consumer 앱을 배포하고 End-to-End 흐름을 검증합니다.

---

## Step 4. Producer 애플리케이션 배포

### 4-1. Docker 이미지 빌드 및 푸시 (필요시)

```bash
cd 03.outbox
chmod +x build-and-push.sh
./build-and-push.sh
```

### 4-2. Kubernetes 배포

```bash
# Producer 배포
kubectl apply -f k8s/producer-deployment.yaml
kubectl apply -f k8s/producer-service.yaml

# 상태 확인
kubectl get pods -n kafka -l app=outbox-producer
kubectl get svc outbox-producer -n kafka
```

> `outbox-producer` 서비스에 외부 IP가 없는 경우 port-forward를 사용합니다.  
> Step 6에서 port-forward 설정을 안내합니다.

---

## Step 5. Consumer 애플리케이션 배포

```bash
# Consumer 배포
kubectl apply -f k8s/consumer-deployment.yaml
kubectl apply -f k8s/consumer-service.yaml

# 상태 확인
kubectl get pods -n kafka -l app=outbox-consumer
```

**Consumer 로그로 Kafka 연결 확인:**
```bash
kubectl logs -n kafka deployment/outbox-consumer --tail=20
```

**정상 로그 예시:**
```
INFO  KafkaListenerContainer : partitions assigned: [outbox.user-0]
```

---

## Step 6. Producer API 검증

### 6-1. port-forward 설정

```bash
# 별도 터미널에서 실행
kubectl port-forward svc/outbox-producer 8080:8080 -n kafka
```

### 6-2. 사용자 생성 API 호출

```bash
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name": "홍길동", "email": "hong@example.com"}'
```

**예상 응답:**
```json
{
  "id": 1,
  "name": "홍길동",
  "email": "hong@example.com"
}
```

### 6-3. outbox_events 테이블 확인

API 호출 후 MariaDB에 이벤트가 저장됐는지 확인합니다.

```bash
kubectl exec -it mariadb-1-0 -n mariadb -c mariadb -- \
  /opt/bitnami/mariadb/bin/mariadb -u skala -p'Skala25a!23$' cloud \
  -e "SELECT id, event_id, aggregate_type, event_type, processed FROM outbox_events ORDER BY id DESC LIMIT 5;"
```

**예상 결과:**
```
+----+--------------------------------------+----------------+------------+-----------+
| id | event_id                             | aggregate_type | event_type | processed |
+----+--------------------------------------+----------------+------------+-----------+
|  2 | b2c3d4e5-f6a7-...                    | user           | CREATED    |         0 |
+----+--------------------------------------+----------------+------------+-----------+
```

### 6-4. Kafka Topic 메시지 확인

```bash
./script/02.check-kafka-topic.sh
```

### 6-5. Consumer 로그로 처리 확인

```bash
kubectl logs -n kafka deployment/outbox-consumer --tail=20
```

**정상 로그 예시:**
```
INFO  OutboxEventListener : Received Debezium USER event: eventId=b2c3d4e5..., eventType=CREATED
INFO  OutboxEventListener : Debezium USER event processed successfully: eventId=b2c3d4e5...
```

---

## Step 7. Producer UI 검증 (localhost:8080)

```bash
kubectl port-forward svc/outbox-producer 8080:8080 -n kafka
```

브라우저에서 접속:
```
http://localhost:8080/
```


---

## 실패 시 점검 항목

### Kafka Topic이 생성되지 않음

```bash
# Connector 상태 확인
kubectl describe kafkaconnector mariadb-outbox-connector-v1.1 -n kafka

# Connect Pod 로그 확인
kubectl logs -n kafka deployment/debezium-source-connect-connect --tail=100 | grep -i error
```

- outbox_events 테이블 존재 여부 확인: `Step 1` 재실행
- `aggregate_type` 필드 값이 소문자인지 확인 (`user`, `order`, `product`)

### Consumer가 메시지를 처리하지 못함

```bash
# Consumer Pod 상태 확인
kubectl describe pod -n kafka -l app=outbox-consumer

# Consumer 로그에서 오류 확인
kubectl logs -n kafka deployment/outbox-consumer --tail=50
```

주요 원인:
- PostgreSQL 연결 오류 (환경변수 확인)
- Kafka bootstrap 주소 오류
- 메시지 역직렬화 오류 (payload 형식 불일치)

### Producer API가 응답하지 않음

```bash
# Producer Pod 상태 확인
kubectl get pods -n kafka -l app=outbox-producer

# Producer 로그 확인
kubectl logs -n kafka deployment/outbox-producer --tail=50
```

주요 원인:
- MariaDB 연결 오류 (환경변수 `SPRING_DATASOURCE_URL` 확인)
- `outbox_events` 테이블 미생성 (`Step 1` 재실행)
