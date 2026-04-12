# Kafka Connect — 실습 가이드

Strimzi 기반 Kafka Connect 클러스터 배포를 위한 커스텀 플러그인 이미지 빌드 및 KafkaConnect CR 적용 실습입니다.

---

## 학습 목표

| 목표 | 내용 |
|------|------|
| 커스텀 이미지 빌드 | Debezium/JDBC 플러그인을 포함한 Connect 이미지 빌드 |
| Source Connect 배포 | debezium-source-connect 클러스터 구성 |
| Sink Connect 배포 | jdbc-sink-connect 클러스터 구성 |
| 운영 상태 확인 | KafkaConnect READY 및 REST API 정상 확인 |

---

## 디렉토리 구성

```
04.connect/
├── Dockerfile                          # 커스텀 Connect 이미지 빌드 정의
├── docker-build.sh                     # 이미지 빌드 스크립트
├── docker-push.sh                      # Harbor registry push 스크립트
├── source-connect-with-debezium.yaml   # KafkaConnect CR — Debezium Source
└── sink-connect.yaml                   # KafkaConnect CR — JDBC Sink
```

---

## 파일 역할 상세

| 파일 | 역할 |
|------|------|
| `Dockerfile` | Strimzi 기본 이미지에 Debezium/JDBC 플러그인 추가 |
| `docker-build.sh` | `skala-kafka-connect:debezium-3.2.3-kafka-4.0` 이미지 빌드 |
| `docker-push.sh` | `amdp-registry.skala-ai.com/library/` registry로 push |
| `source-connect-with-debezium.yaml` | `debezium-source-connect` 클러스터 (Source 전용) |
| `sink-connect.yaml` | `jdbc-sink-connect` 클러스터 (Sink 전용) |

---

## Dockerfile 구성 요소

```
FROM quay.io/strimzi/kafka:0.48.0-kafka-4.0.0
   │
   ├─ Debezium MySQL/MariaDB Source (3.2.3.Final)
   ├─ Debezium PostgreSQL Source (3.2.3.Final)
   ├─ Debezium MongoDB Source (3.2.3.Final)
   ├─ Debezium JDBC Sink (3.2.3.Final)
   ├─ Confluent JDBC Sink (10.8.0)
   ├─ MySQL JDBC Driver
   ├─ PostgreSQL JDBC Driver
   └─ MariaDB JDBC Driver
   │
   ▼
skala-kafka-connect:debezium-3.2.3-kafka-4.0
```

---

## 두 KafkaConnect 클러스터 구성

### Source Connect — debezium-source-connect

| 항목 | 값 |
|------|----|
| 이름 | debezium-source-connect |
| group.id | source-connect-cluster |
| 역할 | DB 변경 이벤트 → Kafka Topic |
| 내부 토픽 | source-connect-configs/offsets/status |
| 커넥터 등록 방식 | KafkaConnector CR (use-connector-resources: "true") |
| replicas | 1 |

### Sink Connect — jdbc-sink-connect

| 항목 | 값 |
|------|----|
| 이름 | jdbc-sink-connect |
| group.id | sink-connect-cluster |
| 역할 | Kafka Topic → 대상 DB |
| 내부 토픽 | sink-configs/offsets/status |
| 커넥터 등록 방식 | KafkaConnector CR |
| 설정 | max.poll.records=500, max.poll.interval.ms=300000 |

---

## 배포 흐름

```
Dockerfile
   │  ./docker-build.sh
   ▼
커스텀 이미지 (로컬)
   │  ./docker-push.sh
   ▼
Harbor Registry (amdp-registry.skala-ai.com/library/)
   │
   ▼
source-connect-with-debezium.yaml
   │  kubectl apply
   ▼
debezium-source-connect (KafkaConnect CR)
   │  Strimzi Operator
   ▼
Source Connect Pod + Service (포트 8083)

sink-connect.yaml
   │  kubectl apply
   ▼
jdbc-sink-connect (KafkaConnect CR)
   │  Strimzi Operator
   ▼
Sink Connect Pod + Service (포트 8083)
```

---

## MariaDB Binlog 사전 요구 사항

Debezium MySQL Source Connector를 사용하려면 MariaDB에 Binlog가 활성화되어 있어야 합니다.

| 설정 | 필요 값 |
|------|---------|
| log_bin | 활성화 |
| binlog_format | ROW |
| binlog_row_image | FULL |
| server-id | 고유 숫자 |

설정 방법은 `backup/BINLOG_GUIDE.md`를 참조하세요.

---

## 실습을 통해 배우는 것

- Strimzi 커스텀 플러그인 이미지 빌드 방법
- Source/Sink Connect 클러스터를 분리 운영하는 이점
- `use-connector-resources` 어노테이션과 KafkaConnector CR 관계
- Kafka Connect REST API(8083)를 통한 상태 확인
- 이후 02.cdc 실습에서 사용할 Connect 클러스터 기반 구성
