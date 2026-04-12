# Cloud Native Data Pattern - Kafka on Kubernetes

Strimzi Operator를 이용하여 Kubernetes 위에 Kafka 클러스터를 구성하는 가이드입니다.

---

## 1. Strimzi Operator 설치

```bash
./install-strimzi.sh
```

스크립트가 수행하는 작업:

1. `kafka` 네임스페이스 생성 (이미 존재하면 유지)
2. Strimzi Operator 최신 버전을 `kafka` 네임스페이스에 설치
3. `strimzi-cluster-operator` Pod가 `Ready` 상태가 될 때까지 최대 5분 대기

설치 완료 후 확인:

```bash
kubectl get pods -n kafka -l name=strimzi-cluster-operator
```

```
NAME                                       READY   STATUS    RESTARTS   AGE
strimzi-cluster-operator-xxxxxxxxx-xxxxx   1/1     Running   0          1m
```

---

## 2. Kafka 클러스터 설치

```bash
kubectl apply -f ./kubernetes/kafka
```

> `k` 는 `kubectl` 의 alias입니다. 동일하게 사용 가능합니다.

---

## 3. kubernetes/kafka/ 파일 설명

| 파일명 | CR 종류 (kind) | API 그룹 | 생성되는 리소스 |
|---|---|---|---|
| `kafka-nodepool.yaml` | `KafkaNodePool` | `kafka.strimzi.io/v1beta2` | Broker + Controller 역할을 겸하는 Node Pool (1 replica, 100Gi 스토리지) |
| `kafka-cluster.yaml` | `Kafka` | `kafka.strimzi.io/v1beta2` | Kafka 클러스터 본체. KRaft 모드(ZooKeeper 없음), 내부 9092/9093, 외부 LoadBalancer 9094 포트 구성 |
| `kafka-topic.yaml` | `KafkaTopic` | `kafka.strimzi.io/v1beta2` | `my-topic` 토픽 (파티션 1, 복제 1, 보존 2시간) |
| `kafka-user.yaml` | `KafkaUser` | `kafka.strimzi.io/v1beta2` | `my-kafka-user` 사용자 (SCRAM-SHA-512 인증, `my-topic` Read/Write/Create/Describe ACL) |
| `kafka-client.yaml` | `Pod` | `v1` | Kafka CLI 도구가 포함된 테스트용 클라이언트 Pod (`confluentinc/cp-kafka:7.4.0`) |
| `harbor-secret.yaml` | `Secret` | `v1` | Private 컨테이너 레지스트리 접근용 이미지 풀 시크릿 (`kubernetes.io/dockerconfigjson` 타입) |

---

## 4. 설치 후 확인

### Pod 상태

```bash
kubectl get pods -n kafka
```

```
NAME                                          READY   STATUS    RESTARTS   AGE
my-kafka-cluster-kafka-pool-0                 1/1     Running   0          3m
strimzi-cluster-operator-xxxxxxxxx-xxxxx      1/1     Running   0          5m
strimzi-entity-operator-xxxxxxxxx-xxxxx       2/2     Running   0          2m
kafka-client                                  1/1     Running   0          1m
```

### Kafka 클러스터 상태

```bash
kubectl get kafka -n kafka
```

```
NAME               DESIRED KAFKA REPLICAS   DESIRED ZK REPLICAS   READY   WARNINGS
my-kafka-cluster   1                                              True
```

### 토픽 / 사용자 확인

```bash
kubectl get kafkatopic -n kafka
kubectl get kafkauser -n kafka
```

```
NAME       CLUSTER            PARTITIONS   REPLICATION FACTOR   READY
my-topic   my-kafka-cluster   1            1                    True

NAME            CLUSTER            AUTHENTICATION   AUTHORIZATION   READY
my-kafka-user   my-kafka-cluster   scram-sha-512    simple          True
```

### 서비스 확인 (외부 접속 포트)

```bash
kubectl get svc -n kafka
```

```
NAME                                             TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
my-kafka-cluster-kafka-bootstrap                 ClusterIP      10.x.x.x        <none>          9091/TCP,9092/TCP,9093/TCP
my-kafka-cluster-kafka-external-bootstrap        LoadBalancer   10.x.x.x        <EXTERNAL_IP>   9094:xxxxx/TCP
my-kafka-cluster-kafka-pool-0                    ClusterIP      10.x.x.x        <none>          9090/TCP,9091/TCP,9092/TCP,9093/TCP
my-kafka-cluster-kafka-pool-0-external-0         LoadBalancer   10.x.x.x        <EXTERNAL_IP>   9094:xxxxx/TCP
```

### 외부 접속 테스트

```bash
# 클라이언트 Pod에서 토픽 목록 확인
kubectl exec -it kafka-client -n kafka -- \
  kafka-topics --bootstrap-server my-kafka-cluster-kafka-external-bootstrap:9094 --list

# 외부에서 직접 접속 (LoadBalancer External IP 사용)
kafka-topics --bootstrap-server <EXTERNAL_IP>:9094 --list
```
