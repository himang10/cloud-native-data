# Kafka on Kubernetes란 무엇인가?

이 문서는 **Strimzi Operator를 이용한 Kubernetes 네이티브 Kafka 클러스터**의 개념과 구성 원리를 설명합니다.

---

## 1. 왜 Kubernetes에서 Kafka를 운영하는가?

전통적인 Kafka 클러스터 운영에는 ZooKeeper, Broker, 네트워크 설정, Java 버전 관리 등 복잡한 인프라 작업이 필요합니다.
Kubernetes 환경에서는 **Strimzi Operator**를 통해 이러한 복잡성을 선언적(Declarative) YAML 구성으로 줄일 수 있습니다.

### 전통적 방식 vs Kubernetes 네이티브

| 항목 | 전통 방식 | Strimzi + Kubernetes |
|------|-----------|----------------------|
| 브로커 배포 | 수동 설치 및 설정 | `Kafka` CR 선언으로 자동 배포 |
| ZooKeeper | 별도 클러스터 필요 | KRaft 모드로 제거 가능 |
| 토픽 생성 | CLI 또는 Admin API | `KafkaTopic` CR |
| 사용자 인증 | 별도 설정 | `KafkaUser` CR + SCRAM-SHA-512 |
| 스케일 아웃 | 수동 노드 추가 | `KafkaNodePool` replicas 조정 |

---

## 2. Strimzi Operator란?

**Strimzi**는 Kubernetes 위에서 Kafka를 운영하기 위한 **오픈소스 Kubernetes Operator**입니다.

```
사용자 → YAML CR 선언
         │
         ▼
  Strimzi Operator (Control Loop)
         │
         ├─→ Kafka Broker Pod 생성/관리
         ├─→ KafkaTopic 생성/삭제
         ├─→ KafkaUser 생성/인증 설정
         └─→ KafkaConnect 커넥터 배포
```

Operator 패턴의 핵심은 **원하는 상태(Desired State)**를 YAML로 선언하면 Operator가 **실제 상태(Actual State)**를 지속적으로 일치시킨다는 점입니다.

---

## 3. KRaft 모드란?

Kafka는 전통적으로 메타데이터 관리에 **ZooKeeper**를 사용했습니다.
Kafka 2.8 이후 도입된 **KRaft(Kafka Raft) 모드**는 ZooKeeper를 제거하고 Kafka 자체 Raft 프로토콜로 메타데이터를 관리합니다.

```
[전통 방식]
Kafka Broker → ZooKeeper (메타데이터, 선출)
                 └─ 별도 포트(2181), 별도 관리 필요

[KRaft 모드]
Kafka Broker+Controller → 자체 Raft 클러스터
                            └─ 의존성 제거, 단순화
```

### KRaft 활성화 방법 (Strimzi)

```yaml
metadata:
  annotations:
    strimzi.io/kraft: enabled     # KRaft 활성화
    strimzi.io/node-pools: enabled # KafkaNodePool 기능 활성화
```

---

## 4. 핵심 Custom Resource 종류

Strimzi는 Kafka 클러스터를 구성하는 각 요소를 **Custom Resource (CR)**로 정의합니다.

### 4-1. KafkaNodePool — 노드 풀

브로커/컨트롤러 역할을 담당하는 노드 그룹을 정의합니다.

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: dual-role          # 풀 이름
spec:
  replicas: 1              # 노드 수
  roles:
    - broker               # 메시지 저장/전달
    - controller           # 클러스터 메타데이터 관리 (KRaft)
  storage:
    type: jbod
    volumes:
      - type: persistent-claim
        size: 10Gi         # 브로커당 스토리지
```

| 필드 | 설명 |
|------|------|
| `roles` | `broker` + `controller` 동시 지정 → 단일 노드에 두 역할 부여 |
| `storage.type: jbod` | 여러 볼륨을 독립적으로 사용 (JBOD: Just a Bunch Of Disks) |

### 4-2. Kafka — 클러스터 전체 설정

Kafka 클러스터 버전, 리스너, 설정 등 클러스터 전반을 정의합니다.

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
spec:
  kafka:
    version: 4.1.0
    listeners:
      - name: plain          # PLAINTEXT (9092) — 내부 통신
      - name: tls            # TLS (9093) — 암호화 통신
      - name: external       # LoadBalancer (9094) — 클러스터 외부 접근
```

**리스너 종류:**

| 리스너 | 포트 | 용도 |
|--------|------|------|
| plain | 9092 | Kubernetes 내부 평문 통신 |
| tls | 9093 | Kubernetes 내부 TLS 암호화 |
| external | 9094 | LoadBalancer를 통한 외부 접근 |

### 4-3. KafkaTopic — 토픽

Kafka 메시지 분류 단위입니다.

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
spec:
  partitions: 1          # 파티션 수 (병렬 처리 단위)
  replicas: 1            # 복제본 수 (고가용성)
  config:
    retention.ms: "7200000"   # 메시지 보관 시간 (2시간)
```

### 4-4. KafkaUser — 사용자 인증 및 권한

SCRAM-SHA-512 인증 + ACL(Access Control List)로 토픽 접근을 제어합니다.

```yaml
spec:
  authentication:
    type: scram-sha-512    # 사용자명/비밀번호 기반 인증
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: my-topic
        operations: [Read, Write, Create, Describe]
```

---

## 5. 네트워크 구성 원리

클러스터 내부/외부 통신 구조:

```
[Kubernetes 클러스터 내부]
Producer/Consumer Pod
   │
   ├─→ my-kafka-cluster-kafka-bootstrap:9092   (plain 내부 서비스)
   └─→ my-kafka-cluster-kafka-bootstrap:9093   (TLS 내부 서비스)

[외부 접근]
외부 클라이언트
   │
   └─→ LoadBalancer :9094 → Kafka Broker Pod
         (AWS NLB: service.beta.kubernetes.io/aws-load-balancer-type)
```

---

## 6. 학습 포인트 정리

| 개념 | 핵심 내용 |
|------|-----------|
| Operator 패턴 | YAML 선언 → Operator가 실제 상태 유지 |
| KRaft 모드 | ZooKeeper 없이 Kafka 자체 Raft 메타데이터 관리 |
| KafkaNodePool | 브로커와 컨트롤러를 담당하는 노드 그룹 정의 |
| 다중 리스너 | 내부(9092/9093)와 외부(9094) 동시 제공 |
| KafkaUser + ACL | 토픽별 읽기/쓰기 권한 선언적 관리 |
| SCRAM-SHA-512 | 비밀번호 기반 클라이언트 인증 메커니즘 |
