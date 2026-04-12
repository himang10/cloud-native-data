# Kafka Connect — 실행 가이드

이 문서는 커스텀 플러그인 이미지를 빌드하고 Strimzi 기반 Kafka Connect 클러스터를 배포하는 단계별 절차를 안내합니다.

---

## 사전 준비 사항

| 항목 | 확인 명령 | 기대 결과 |
|------|-----------|-----------|
| Docker 실행 | `docker info` | Docker daemon 정보 표시 |
| Registry 접근 | `docker login amdp-registry.skala-ai.com` | Login Succeeded |
| Kafka 클러스터 | `kubectl get kafka -n kafka` | my-kafka-cluster Ready |
| kubectl 연결 | `kubectl cluster-info` | 클러스터 API 서버 주소 표시 |

Kafka 클러스터가 없다면 `01.install/03.kafka` 실습을 먼저 완료하세요.

---

## Step 1: 커스텀 이미지 빌드

Debezium과 JDBC 플러그인이 포함된 커스텀 Kafka Connect 이미지를 빌드합니다.

```bash
cd 01.install/04.connect
./docker-build.sh
```

빌드 과정에서 다음 플러그인이 추가됩니다:

| 플러그인 | 버전 |
|---------|------|
| Debezium MySQL/MariaDB Source | 3.2.3.Final |
| Debezium PostgreSQL Source | 3.2.3.Final |
| Debezium MongoDB Source | 3.2.3.Final |
| Debezium JDBC Sink | 3.2.3.Final |
| Confluent JDBC Sink | 10.8.0 |

**빌드 완료 확인:**
```bash
docker images | grep skala-kafka-connect
```

**예상 출력:**
```
skala-kafka-connect   debezium-3.2.3-kafka-4.0   <이미지 ID>   <날짜>   1.2GB
```

---

## Step 2: Registry에 이미지 Push

빌드한 이미지를 Harbor private registry에 업로드합니다.

```bash
./docker-push.sh
```

**예상 출력:**
```
The push refers to repository [amdp-registry.skala-ai.com/library/skala-kafka-connect]
...
debezium-3.2.3-kafka-4.0: digest: sha256:... size: ...
```

> 빌드와 Push는 환경에 따라 수 분이 소요될 수 있습니다.

---

## Step 3: (필요 시) MariaDB Binlog 설정 확인

Debezium MySQL Source Connector를 사용하려면 MariaDB Binlog가 활성화되어 있어야 합니다.

**Binlog 상태 확인:**
```bash
kubectl exec -it <mariadb-pod> -n database -- \
  mysql -u root -p -e "SHOW VARIABLES LIKE 'log_bin%'; SHOW VARIABLES LIKE 'binlog_format';"
```

**기대 출력:**
```
+------------------------+-------+
| Variable_name          | Value |
+------------------------+-------+
| log_bin                | ON    |
| log_bin_basename       | ...   |
| binlog_format          | ROW   |
+------------------------+-------+
```

Binlog가 비활성화된 경우 `backup/BINLOG_GUIDE.md`를 참고하여 MariaDB Helm 설정을 수정하세요.

---

## Step 4: Source Connect 배포

Debezium Source 커넥터를 실행할 KafkaConnect 클러스터를 배포합니다.

```bash
kubectl apply -f source-connect-with-debezium.yaml
```

**예상 출력:**
```
kafkaconnect.kafka.strimzi.io/debezium-source-connect created
```

**준비 완료 대기:**
```bash
kubectl wait kafkaconnect/debezium-source-connect \
  --for=condition=Ready \
  --timeout=300s \
  -n kafka
```

**상태 확인:**
```bash
kubectl get kafkaconnect -n kafka
```

| NAME | DESIRED REPLICAS | READY |
|------|-----------------|-------|
| debezium-source-connect | 1 | True |

**Pod 확인:**
```bash
kubectl get pods -n kafka | grep debezium-source-connect
```

| NAME | READY | STATUS |
|------|-------|--------|
| debezium-source-connect-connect-0 | 1/1 | Running |

---

## Step 5: Sink Connect 배포

JDBC Sink 커넥터를 실행할 KafkaConnect 클러스터를 배포합니다.

```bash
kubectl apply -f sink-connect.yaml
```

**준비 완료 대기:**
```bash
kubectl wait kafkaconnect/jdbc-sink-connect \
  --for=condition=Ready \
  --timeout=300s \
  -n kafka
```

**상태 확인:**
```bash
kubectl get kafkaconnect -n kafka
```

| NAME | DESIRED REPLICAS | READY |
|------|-----------------|-------|
| debezium-source-connect | 1 | True |
| jdbc-sink-connect | 1 | True |

---

## Step 6: REST API로 플러그인 목록 확인

Kafka Connect는 8083 포트에서 REST API를 제공합니다. Port-forward로 플러그인 목록을 확인합니다.

**Source Connect 플러그인 확인:**
```bash
# 포트 포워딩 (별도 터미널에서 실행)
kubectl port-forward svc/debezium-source-connect-connect-api 8083:8083 -n kafka &

# 플러그인 목록 조회
curl -s http://localhost:8083/connector-plugins | jq '.[].class'
```

**예상 출력 (일부):**
```json
"io.debezium.connector.mysql.MySqlConnector"
"io.debezium.connector.postgresql.PostgresConnector"
"io.debezium.connector.mongodb.MongoDbConnector"
"io.debezium.connector.jdbc.JdbcSinkConnector"
```

**Sink Connect 플러그인 확인:**
```bash
kubectl port-forward svc/jdbc-sink-connect-connect-api 8084:8083 -n kafka &
curl -s http://localhost:8084/connector-plugins | jq '.[].class'
```

---

## Step 7: 로그 확인

각 Connect 클러스터의 로그로 정상 동작을 확인합니다.

**Source Connect 로그:**
```bash
kubectl logs -n kafka \
  $(kubectl get pod -n kafka -l strimzi.io/cluster=debezium-source-connect -o name | head -1) \
  --tail=30
```

**정상 로그 예시:**
```
INFO Kafka Connect started (org.apache.kafka.connect.runtime.ConnectMetrics)
INFO Starting connector manager (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
INFO Worker started (org.apache.kafka.connect.runtime.ConnectMetrics)
```

**Sink Connect 로그:**
```bash
kubectl logs -n kafka \
  $(kubectl get pod -n kafka -l strimzi.io/cluster=jdbc-sink-connect -o name | head -1) \
  --tail=30
```

---

## 문제 해결

### 이미지 Pull 실패 (ImagePullBackOff)

```bash
kubectl describe pod <connect-pod-name> -n kafka | grep -A 5 Events
```

주요 원인:
- Registry 인증 실패 → harbor-secret.yaml이 적용되었는지 확인
- 이미지 태그 오류 → Dockerfile과 KafkaConnect yaml의 이미지명 일치 확인

harbor-secret.yaml 적용:
```bash
kubectl apply -f ../03.kafka/harbor-secret.yaml
```

그리고 KafkaConnect YAML에 imagePullSecrets 설정이 있는지 확인하세요.

---

### Connect 클러스터가 Ready 상태가 되지 않는 경우

```bash
kubectl describe kafkaconnect debezium-source-connect -n kafka | tail -20
```

주요 원인:
- Kafka 클러스터 bootstrapServers 주소 오류
- 내부 토픽 생성 실패 (Kafka 클러스터가 준비되지 않은 경우)

---

### REST API 응답 없음

```bash
# Connect 서비스 확인
kubectl get svc -n kafka | grep connect

# Port-forward가 실행 중인지 확인
ps aux | grep port-forward
```

---

### 커넥터 등록 후 FAILED 상태

```bash
# 커넥터 상태 확인
curl -s http://localhost:8083/connectors/<connector-name>/status | jq
```

**예상 출력 (오류 시):**
```json
{
  "name": "mariadb-source",
  "connector": {"state": "FAILED", "worker_id": "..."},
  "tasks": [{"id": 0, "state": "FAILED", "trace": "..."}]
}
```

오류 trace를 확인하여 DB 접속 정보, Binlog 활성화 여부 등을 점검하세요.

