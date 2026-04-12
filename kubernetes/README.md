# Kafka 기반 Cloud Native Data 실습

Strimzi + Debezium을 이용한 Kubernetes 환경의 CDC·Outbox 패턴 실습 프로젝트입니다.

---

## 전체 구성

```
MariaDB (Source DB)
   │  Binlog (ROW)
   ▼
Debezium Source Connect
   │  Kafka Topic
   ▼
Kafka Cluster (KRaft, Strimzi)
   │  Kafka Topic
   ▼
JDBC Sink Connect
   │
   ▼
PostgreSQL / MongoDB (Target DB)
```

---

## 디렉토리 구성

```
kubernetes/
├── 01.install/                     # 인프라 설치
│   ├── 01.database/                # MariaDB, PostgreSQL, MongoDB, Redis 설치
│   ├── 02.strimzi-operator/        # Strimzi Operator 설치
│   ├── 03.kafka/                   # Kafka 클러스터 배포 (KRaft 모드)
│   └── 04.connect/                 # Kafka Connect 커스텀 이미지 빌드 및 배포
│
├── 02.cdc/                         # CDC(Change Data Capture) 실습
│   ├── mariadb-source-connector.yaml
│   ├── postgresql-sink-connector.yaml
│   ├── mongodb-sink-connector.yaml
│   └── script/                     # Binlog 확인, 테이블 생성, 데이터 삽입 스크립트
│
└── 03.outbox/                      # Outbox 패턴 실습
    ├── connectors/                 # Debezium Outbox Connector
    ├── producer/                   # Spring Boot Producer (outbox_events 기록)
    ├── consumer/                   # Spring Boot Consumer (Kafka 이벤트 소비)
    ├── k8s/                        # Kubernetes 배포 YAML
    └── script/                     # 이벤트 생성·Kafka 확인·Consumer 테스트 스크립트
```

---

## 실습 순서

| 순서 | 디렉토리 | 내용 |
|------|----------|------|
| 1 | `01.install/01.database` | DB 설치 (MariaDB, PostgreSQL, MongoDB) |
| 2 | `01.install/02.strimzi-operator` | Strimzi Operator 설치 |
| 3 | `01.install/03.kafka` | Kafka 클러스터 배포 |
| 4 | `01.install/04.connect` | Connect 커스텀 이미지 빌드 및 배포 |
| 5 | `02.cdc` | Source/Sink Connector로 DB 간 실시간 동기화 |
| 6 | `03.outbox` | Outbox 패턴으로 안전한 이벤트 발행 |

각 디렉토리의 `WHAT.md` (개념), `README.md` (구성), `TEST-GUIDE.md` (실행 절차)를 순서대로 참고하세요.

---

## 사전 요구 사항

- Kubernetes 클러스터 (1.25+)
- kubectl
- Helm 3
- Docker (Connect 이미지 빌드 시)
- Harbor private registry 접근 권한
