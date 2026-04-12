# Kafka on Kubernetes — 실습 가이드

Strimzi Operator를 이용해 Kubernetes 위에 Kafka 클러스터를 배포하고 메시지 송수신을 검증하는 실습입니다.

---

## 학습 목표

| 목표 | 내용 |
|------|------|
| Kafka 클러스터 배포 | KafkaNodePool + Kafka CR로 KRaft 클러스터 구성 |
| 토픽 및 사용자 관리 | KafkaTopic, KafkaUser CR을 통한 선언적 관리 |
| 메시지 송수신 검증 | 클라이언트 파드에서 Producer/Consumer 실행 및 확인 |
| 외부 접근 구성 | LoadBalancer 리스너(9094)를 통한 외부 연결 확인 |

---

## 디렉토리 구성

```
03.kafka/
├── 01.kafka-nodepool.yaml          # KafkaNodePool CR — 브로커/컨트롤러 노드 풀
├── 02.kafka-cluster.yaml           # Kafka CR — 클러스터 전체 설정
├── kafka-topic.yaml                # KafkaTopic CR — 토픽 생성
├── kafka-user.yaml                 # KafkaUser CR — 인증 및 ACL 설정
├── kafka-client.yaml               # 테스트 파드 — 메시지 송수신 검증
├── harbor-secret.yaml              # private registry 이미지 pull secret
└── backup/                         # 기존 가이드 문서 원본
    └── user-guide.md
```

---

## 파일 역할 상세

### YAML 파일

| 파일 | Kind | 역할 |
|------|------|------|
| `01.kafka-nodepool.yaml` | KafkaNodePool | 브로커+컨트롤러 dual-role, 1 replica, 10Gi JBOD 스토리지 |
| `02.kafka-cluster.yaml` | Kafka | v4.1.0, KRaft 모드, 3개 리스너(plain/tls/external LB) |
| `kafka-topic.yaml` | KafkaTopic | `my-topic`, 1 파티션, 1 복제본, 2시간 보관 |
| `kafka-user.yaml` | KafkaUser | `my-kafka-user`, SCRAM-SHA-512, my-topic R/W ACL |
| `kafka-client.yaml` | Pod | `cp-kafka:7.4.0` 테스트 클라이언트, sleep infinity |
| `harbor-secret.yaml` | Secret | private registry 이미지 pull 인증 시크릿 |

---

## 배포 흐름

```
01.kafka-nodepool.yaml
   │ kubectl apply
   ▼
KafkaNodePool CR 생성 (dual-role: broker + controller)
   │
   ▼
02.kafka-cluster.yaml
   │ kubectl apply
   ▼
Kafka CR 생성 → Strimzi Operator가 Broker Pod + Service 생성
   │
   ├─→ plain:9092   (내부 평문)
   ├─→ tls:9093     (내부 TLS)
   └─→ external:9094 (LoadBalancer)

Cluster READY 확인 후
   │
   ├─→ kafka-topic.yaml  → KafkaTopic 생성
   ├─→ kafka-user.yaml   → KafkaUser + Secret 생성
   └─→ kafka-client.yaml → 테스트 파드 배포
```

---

## 주요 구성 상세

### KafkaNodePool 설정

| 항목 | 값 | 설명 |
|------|----|------|
| replicas | 1 | 단일 노드 (개발/실습 환경) |
| roles | broker, controller | 단일 노드에 두 역할 부여 |
| storage | JBOD, 10Gi | 독립 볼륨 마운트 방식 |
| JVM | -Xms1g / -Xmx1g | Kafka Broker 힙 메모리 |

### Kafka 클러스터 설정

| 항목 | 값 | 설명 |
|------|----|------|
| version | 4.1.0 | Kafka 버전 |
| KRaft | strimzi.io/kraft: enabled | ZooKeeper 미사용 |
| external listener | AWS NLB (service.beta.kubernetes.io/aws-load-balancer-type: nlb) | 외부 접근용 NLB |
| offsets.topic.replication.factor | 1 | 단일 브로커에 맞는 설정 |

### KafkaUser 인증 / 권한

| 항목 | 값 |
|------|----|
| 인증 방식 | SCRAM-SHA-512 (비밀번호 기반) |
| 토픽 권한 | my-topic — Read, Write, Create, Describe |
| 컨슈머 그룹 권한 | my-group — Read |

---

## 실습을 통해 배우는 것

- Strimzi Operator를 통한 Kafka 클러스터 선언적 배포
- KRaft 모드 구조와 ZooKeeper 비의존 설계
- KafkaTopic / KafkaUser CR을 통한 토픽/사용자 관리
- SCRAM-SHA-512 인증과 ACL 기반 접근 제어
- Kubernetes LoadBalancer를 통한 외부 Kafka 연결 방법
