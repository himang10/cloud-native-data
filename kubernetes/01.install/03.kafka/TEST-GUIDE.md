# Kafka on Kubernetes — 실행 가이드

이 문서는 Strimzi Operator 기반 Kafka 클러스터를 단계별로 배포하고 메시지 송수신을 직접 검증하는 절차를 안내합니다.

---

## 사전 준비 사항

| 항목 | 확인 명령 | 기대 결과 |
|------|-----------|-----------|
| kubectl 연결 | `kubectl cluster-info` | 클러스터 API 서버 주소 표시 |
| Strimzi Operator 실행 | `kubectl get pods -n kafka \| grep strimzi` | strimzi-cluster-operator Running |
| kafka 네임스페이스 | `kubectl get ns kafka` | Active 상태 |
| StorageClass | `kubectl get storageclass` | 기본 StorageClass 존재 |

Strimzi Operator가 없다면 `01.install/02.strimzi-operator/install-strimzi.sh`를 먼저 실행하세요.

---

## Step 1: KafkaNodePool 배포

브로커와 컨트롤러 역할을 담당할 노드 풀을 생성합니다.

```bash
kubectl apply -f 01.kafka-nodepool.yaml
```

**예상 출력:**
```
kafkanodepool.kafka.strimzi.io/dual-role created
```

**생성 확인:**
```bash
kubectl get kafkanodepool -n kafka
```

| NAME | DESIRED REPLICAS | ROLES |
|------|-----------------|-------|
| dual-role | 1 | ["broker","controller"] |

---

## Step 2: Kafka 클러스터 배포

전체 Kafka 클러스터를 생성합니다. 내부적으로 Strimzi Operator가 Pod, Service, ConfigMap을 자동으로 생성합니다.

```bash
kubectl apply -f 02.kafka-cluster.yaml
```

**예상 출력:**
```
kafka.kafka.strimzi.io/my-kafka-cluster created
```

---

## Step 3: 클러스터 준비 완료 대기

Kafka 클러스터가 완전히 준비될 때까지 기다립니다.

```bash
kubectl wait kafka/my-kafka-cluster \
  --for=condition=Ready \
  --timeout=300s \
  -n kafka
```

**예상 출력:**
```
kafka.kafka.strimzi.io/my-kafka-cluster condition met
```

**상태 확인:**
```bash
kubectl get kafka -n kafka
```

| NAME | DESIRED KAFKA REPLICAS | READY |
|------|------------------------|-------|
| my-kafka-cluster | 1 | True |

**Broker Pod 확인:**
```bash
kubectl get pods -n kafka -l strimzi.io/cluster=my-kafka-cluster
```

| NAME | READY | STATUS |
|------|-------|--------|
| my-kafka-cluster-dual-role-0 | 1/1 | Running |

---

## Step 4: KafkaTopic 생성

메시지를 주고받을 토픽을 생성합니다.

```bash
kubectl apply -f kafka-topic.yaml
```

**생성 확인:**
```bash
kubectl get kafkatopic -n kafka
```

| NAME | CLUSTER | PARTITIONS | REPLICATION FACTOR | READY |
|------|---------|------------|--------------------|-------|
| my-topic | my-kafka-cluster | 1 | 1 | True |

---

## Step 5: KafkaUser 생성

SCRAM-SHA-512 인증으로 토픽에 접근할 사용자를 생성합니다.

```bash
kubectl apply -f kafka-user.yaml
```

**생성 확인:**
```bash
kubectl get kafkauser -n kafka
```

| NAME | CLUSTER | AUTHENTICATION | AUTHORIZATION | READY |
|------|---------|----------------|---------------|-------|
| my-kafka-user | my-kafka-cluster | scram-sha-512 | simple | True |

KafkaUser가 Ready 상태가 되면 Strimzi가 자동으로 비밀번호 시크릿을 생성합니다:

```bash
kubectl get secret my-kafka-user -n kafka
```

---

## Step 6: 테스트 파드 배포

Kafka 클라이언트 도구가 설치된 테스트 파드를 배포합니다.

> Private registry를 사용하는 경우 harbor-secret.yaml을 먼저 적용하세요.

```bash
# (필요한 경우) registry 시크릿 적용
kubectl apply -f harbor-secret.yaml

# 테스트 파드 배포
kubectl apply -f kafka-client.yaml
```

**파드 준비 대기:**
```bash
kubectl wait pod/kafka-client \
  --for=condition=Ready \
  --timeout=120s \
  -n kafka
```

---

## Step 7: 메시지 전송 (Producer)

새 터미널을 열고 Producer로 메시지를 전송합니다.

```bash
kubectl exec -it kafka-client -n kafka -- \
  kafka-console-producer \
    --broker-list my-kafka-cluster-kafka-bootstrap:9092 \
    --topic my-topic
```

프롬프트가 나타나면 메시지를 입력합니다:

```
> Hello Kafka!
> Test message 1
> Test message 2
```

`Ctrl+C`로 종료합니다.

---

## Step 8: 메시지 수신 (Consumer)

다른 터미널에서 Consumer로 메시지를 수신합니다.

```bash
kubectl exec -it kafka-client -n kafka -- \
  kafka-console-consumer \
    --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092 \
    --topic my-topic \
    --from-beginning
```

**예상 출력:**
```
Hello Kafka!
Test message 1
Test message 2
```

`Ctrl+C`로 종료합니다.

---

## Step 9: SCRAM 인증 테스트 (선택)

KafkaUser 인증을 사용하는 연결 테스트입니다.

**비밀번호 추출:**
```bash
kubectl get secret my-kafka-user \
  -n kafka \
  -o jsonpath='{.data.password}' \
  | base64 --decode
```

**JAAS 설정 파일 생성 (파드 내부):**
```bash
kubectl exec -it kafka-client -n kafka -- bash -c '
cat > /tmp/jaas.conf << EOF
KafkaClient {
  org.apache.kafka.common.security.scram.ScramLoginModule required
  username="my-kafka-user"
  password="<위에서 추출한 비밀번호>";
};
EOF'
```

**인증 연결 테스트:**
```bash
kubectl exec -it kafka-client -n kafka -- \
  kafka-topics \
    --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092 \
    --list \
    --command-config /tmp/client.properties
```

---

## Step 10: 서비스 엔드포인트 확인

```bash
# 서비스 목록 확인
kubectl get svc -n kafka | grep my-kafka-cluster

# 외부 LoadBalancer IP 확인
kubectl get svc my-kafka-cluster-kafka-external-bootstrap -n kafka
```

**예상 출력 (외부 LB):**
```
NAME                                           TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)
my-kafka-cluster-kafka-external-bootstrap      LoadBalancer   10.0.x.x     a1b2c3d4.elb..   9094:xxxxx/TCP
```

---

## 문제 해결

### 클러스터가 Ready 상태가 되지 않는 경우

```bash
# Operator 로그 확인
kubectl logs -n kafka deployment/strimzi-cluster-operator --tail=50

# Kafka Pod 이벤트 확인
kubectl describe pod my-kafka-cluster-dual-role-0 -n kafka | grep -A 10 Events
```

주요 원인:
- `StorageClass`가 존재하지 않음 → `kubectl get sc` 확인
- 메모리 부족 → Pod 이벤트에 `OOMKilled` 또는 `Pending` 확인

---

### KafkaTopic이 Ready 상태가 되지 않는 경우

```bash
kubectl describe kafkatopic my-topic -n kafka
```

주요 원인:
- Kafka 클러스터가 아직 준비되지 않음 → Step 3 완료 후 재시도
- `cluster` 레이블이 Kafka 클러스터 이름과 불일치

---

### 메시지가 수신되지 않는 경우

```bash
# 토픽 정보 확인
kubectl exec -it kafka-client -n kafka -- \
  kafka-topics \
    --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092 \
    --describe \
    --topic my-topic
```

- `--from-beginning` 옵션 확인 (이미 오프셋이 지났을 경우)
- Producer가 올바른 토픽 이름으로 전송했는지 확인

---

## 전체 정리 (실습 종료 후)

```bash
kubectl delete -f kafka-client.yaml
kubectl delete -f kafka-user.yaml
kubectl delete -f kafka-topic.yaml
kubectl delete -f 02.kafka-cluster.yaml
kubectl delete -f 01.kafka-nodepool.yaml
```
