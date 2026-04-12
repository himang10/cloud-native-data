# CDC 실습 실행 가이드

> CDC 개념 이해 → [WHAT.md](WHAT.md)  
> 프로젝트 구성 이해 → [README.md](README.md)

---

## 사전 준비 사항

### 1. 인프라 상태 확인

Strimzi Operator, Kafka 클러스터, KafkaConnect 클러스터가 모두 Running 상태인지 확인합니다.

```bash
# Kafka 클러스터 확인
kubectl get kafka -n kafka

# KafkaConnect 클러스터 확인 (Source / Sink 각각)
kubectl get kafkaconnect -n kafka
```

**정상 출력 예시:**
```
NAME                      DESIRED KAFKA REPLICAS   READY
my-kafka-cluster          3                        True

NAME                        REPLICAS   READY
debezium-source-connect     1          True
jdbc-sink-connect           1          True
```

> `READY = True`가 아닌 경우 해당 Pod의 로그를 먼저 확인하세요.  
> ```bash
> kubectl get pods -n kafka
> kubectl logs -n kafka deployment/debezium-source-connect-connect --tail=50
> ```

---

### 2. MariaDB Binlog 상태 확인

Debezium Source Connector는 MariaDB Binlog가 ROW 형식으로 활성화되어 있어야 동작합니다.

```bash
cd 02.cdc
chmod +x script/check-binlog-status.sh
./script/check-binlog-status.sh
```

**정상 출력 예시:**
```
========================================== 
 MariaDB Binlog 상태 확인
==========================================

 설정 검증

 Binlog 활성화: ON
 Binlog 형식: ROW (CDC 지원)
```

**확인 항목:**
| 항목 | 필요 값 | 의미 |
|------|---------|------|
| `log_bin` | `ON` | Binlog 기능 활성화 |
| `binlog_format` | `ROW` | 행 수준 변경 기록 (Debezium 필수) |
| `binlog_row_image` | `FULL` | 변경 전/후 전체 컬럼 기록 |
| CDC 사용자 권한 | `REPLICATION SLAVE`, `REPLICATION CLIENT` | Binlog 스트리밍 권한 |

---

## Step 1. Source Connector 배포

```bash
# 작업 디렉토리로 이동
cd 02.cdc

# Source Connector 배포
kubectl apply -f mariadb-source-connector.yaml
```

**배포 확인:**
```bash
kubectl get kafkaconnector -n kafka
```

**예상 출력:**
```
NAME                                  CLUSTER                   CONNECTOR CLASS                              MAX TASKS   READY
mariadb-source-cdc-connector-v1.0.3   debezium-source-connect   io.debezium.connector.mysql.MySqlConnector   1           True
```

**확인 포인트:**
- `READY = True` 인지 확인
- `True`가 아닌 경우 아래 명령으로 상세 오류를 확인합니다.

```bash
kubectl describe kafkaconnector mariadb-source-cdc-connector-v1.0.3 -n kafka
```

> `READY = False`의 주요 원인:
> - MariaDB 연결 실패 (hostname, 포트, 자격증명 오류)
> - Binlog 비활성화 또는 권한 부족
> - `strimzi.io/cluster` 레이블이 잘못 지정됨

---

## Step 2. Connector 상태 상세 확인

```bash
./script/check-connector-status.sh mariadb-source-cdc-connector-v1.0.3
```

**정상 출력:**
```
✅ Connector 상태: RUNNING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Task 상태
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Task 0: RUNNING
   Worker: 10.0.1.xxx:8083
```

---

## Step 3. 테스트 데이터 삽입 및 CDC 검증

### 3-1. 테스트 데이터 삽입

```bash
# users 테이블에 3개 레코드 삽입
./script/insert-test-data.sh insert 3
```

**예상 출력:**
```
Inserting 3 test records...
✅ Inserted record 1: user_test_xxx
✅ Inserted record 2: user_test_yyy
✅ Inserted record 3: user_test_zzz
Total records: 3
```

### 3-2. Kafka Topic 확인 (Conduktor UI)

**Step 1. 외부 접속 주소 확인:**
```bash
kubectl get svc my-kafka-cluster-kafka-external-bootstrap -n kafka
```

**출력 예시:**
```
NAME                                          TYPE           EXTERNAL-IP                                    PORT(S)
my-kafka-cluster-kafka-external-bootstrap     LoadBalancer   a1961f...elb.amazonaws.com                    9094:32100/TCP
```

**Step 2. Conduktor에서 Topic 확인:**

1. 브라우저에서 Conduktor 접속
2. Clusters → 해당 클러스터 선택
3. Topics 탭에서 `mariadb-cdc.cloud.users` 검색
4. Messages 탭에서 최신 메시지 확인

**메시지 예시 (CDC Envelope 형식):**
```json
{
  "before": null,
  "after": {
    "id": 1,
    "name": "user_test_xxx",
    "email": "test_xxx@example.com"
  },
  "op": "c",
  "ts_ms": 1234567890000
}
```

| `op` 값 | 의미 |
|---------|------|
| `c` | CREATE (INSERT) |
| `u` | UPDATE |
| `d` | DELETE |
| `r` | READ (초기 스냅샷) |

---

## Step 4. Sink Connector 배포

### PostgreSQL Sink 배포

```bash
kubectl apply -f postgresql-sink-connector.yaml

# 상태 확인
kubectl get kafkaconnector postgres-sink-cdc-connector-v1.0.0 -n kafka
```

### MongoDB Sink 배포

```bash
kubectl apply -f mongodb-sink-connector.yaml

# 상태 확인
kubectl get kafkaconnector mongodb-sink-cdc-connector-v1.0.0 -n kafka
```

### 전체 Connector 상태 한 번에 확인

```bash
kubectl get kafkaconnector -n kafka
```

**예상 출력:**
```
NAME                                  CLUSTER                   READY
mariadb-source-cdc-connector-v1.0.3   debezium-source-connect   True
postgres-sink-cdc-connector-v1.0.0    jdbc-sink-connect         True
mongodb-sink-cdc-connector-v1.0.0     jdbc-sink-connect         True
```

---

## Step 5. 데이터 동기화 검증

### PostgreSQL 동기화 확인

```bash
# PostgreSQL Pod에 접속
kubectl exec -it postgres-1-postgresql-0 -n postgres -- psql -U skala -d cloud

# cdc_users 테이블 조회
SELECT * FROM cdc_users ORDER BY id DESC LIMIT 5;
```

**예상 결과:** MariaDB에 삽입한 users 데이터가 `cdc_users` 테이블에 반영되어 있어야 합니다.

### UPDATE 전파 확인

```bash
# MariaDB에서 데이터 수정
./script/insert-test-data.sh update 2

# PostgreSQL에서 변경 반영 확인 (10초 이내)
kubectl exec -it postgres-1-postgresql-0 -n postgres -- psql -U skala -d cloud \
  -c "SELECT id, name, updated_at FROM cdc_users ORDER BY updated_at DESC LIMIT 3;"
```

### DELETE 전파 확인

```bash
# MariaDB에서 데이터 삭제
./script/insert-test-data.sh delete 1

# PostgreSQL에서 삭제 반영 확인
kubectl exec -it postgres-1-postgresql-0 -n postgres -- psql -U skala -d cloud \
  -c "SELECT COUNT(*) FROM cdc_users;"
```

---

## 실패 시 점검 항목

### Connector가 READY = False

```bash
# 상세 오류 확인
kubectl describe kafkaconnector <connector-name> -n kafka

# Connect Pod 로그 확인
kubectl logs -n kafka deployment/debezium-source-connect-connect --tail=100
kubectl logs -n kafka deployment/jdbc-sink-connect-connect --tail=100
```

주요 원인:
- DB 연결 정보 오류 (hostname, password)
- `strimzi.io/cluster` 레이블이 Connect 클러스터 이름과 불일치
- MariaDB Binlog 미설정 또는 권한 부족

### Kafka Topic에 메시지가 생성되지 않음

```bash
# Source Connector Task 오류 확인
./script/check-connector-status.sh mariadb-source-cdc-connector-v1.0.3

# MariaDB Binlog 위치 확인
./script/check-binlog-status.sh
```

> Binlog 오프셋 불일치 오류가 발생하면 Connector를 삭제 후 재배포합니다.
> ```bash
> kubectl delete kafkaconnector mariadb-source-cdc-connector-v1.0.3 -n kafka
> kubectl apply -f mariadb-source-connector.yaml
> ```

### Sink DB에 데이터가 반영되지 않음

```bash
# Sink Connector 상태 확인
./script/check-connector-status.sh postgres-sink-cdc-connector-v1.0.0

# Dead Letter Queue 확인 (처리 실패 메시지)
kubectl exec -it my-kafka-cluster-kafka-0 -n kafka -- \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic dlq-postgresql-sink --from-beginning --max-messages 5
```

주요 원인:
- Sink DB 연결 오류
- 스키마 불일치 (컬럼 타입 차이)
- `topics.regex` 패턴이 Source Topic 이름과 불일치
