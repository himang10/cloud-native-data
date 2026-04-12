# Cloud Native Data — CDC & Outbox Pattern 실습

Strimzi + Debezium 기반의 Kubernetes / Local Docker 환경에서  
**CDC(Change Data Capture)** 와 **Outbox Pattern** 을 직접 구성하고 검증하는 실습 저장소입니다.

---

## 전체 아키텍처

```
MariaDB (Source DB)
   │  Binlog (ROW)
   ▼
Debezium Source Connector
   │  Kafka Topic
   ▼
Kafka Cluster (KRaft, Strimzi)
   │
   ├──▶ JDBC Sink Connector ──▶ PostgreSQL
   └──▶ MongoDB Sink Connector ──▶ MongoDB
```

**Outbox Pattern** 흐름:
```
Producer (Spring Boot) ──▶ MariaDB outbox_events
                                  │ Debezium EventRouter SMT
                                  ▼
                           Kafka Topic (outbox.*)
                                  │
                           Consumer (Spring Boot) ──▶ PostgreSQL
```

---

## 저장소 구조

```
.
├── kubernetes/          # Kubernetes 환경 실습
│   ├── 01.install/      # 인프라 설치 (DB, Strimzi, Kafka, Connect)
│   ├── 02.cdc/          # CDC 실습 (Source / Sink Connector YAML)
│   └── 03.outbox/       # Outbox Pattern 실습 (Spring Boot + K8s 배포)
│
└── local/               # Local Docker Compose 환경 실습
    ├── kafka/            # Kafka + Debezium UI
    ├── kafka-connect/    # Kafka Connect 커스텀 실행
    ├── kafka-source-connector/   # CDC Source Connector
    ├── kafka-sink-connector/     # JDBC Sink Connector
    ├── outbox-source-connector/  # Outbox Source Connector
    ├── mariadb/          # MariaDB 컨테이너
    └── pgvector/         # PostgreSQL(pgvector) 컨테이너
```

---

## 실습 환경별 시작 가이드

### Kubernetes 환경

| 순서 | 경로 | 내용 |
|------|------|------|
| 1 | `kubernetes/01.install/01.database` | MariaDB · PostgreSQL · MongoDB 설치 |
| 2 | `kubernetes/01.install/02.strimzi-operator` | Strimzi Operator 설치 |
| 3 | `kubernetes/01.install/03.kafka` | Kafka 클러스터 배포 (KRaft) |
| 4 | `kubernetes/01.install/04.connect` | Connect 커스텀 이미지 빌드 및 배포 |
| 5 | `kubernetes/02.cdc` | CDC 파이프라인 (Source → Kafka → Sink) |
| 6 | `kubernetes/03.outbox` | Outbox Pattern (Producer → Kafka → Consumer) |

> 각 디렉토리의 `WHAT.md` → `README.md` → `TEST-GUIDE.md` 순서로 참고하세요.

---

## 사전 요구 사항

| 항목 | 버전 |
|------|------|
| Kubernetes | 1.25+ (kubernetes 환경) |
| Helm | 3+ |
| Docker / Docker Compose | 최신 |
| kubectl | 클러스터 버전 호환 |

---

## 주요 기술 스택

- **Kafka** — KRaft 모드 (Strimzi Operator)
- **Debezium** — MariaDB Source Connector, EventRouter SMT
- **JDBC Sink Connector** — PostgreSQL
- **MongoDB Sink Connector** — MongoDB
- **Spring Boot** — Outbox Producer / Consumer (kubernetes/03.outbox)

