# Kafka Connect란 무엇인가?

이 문서는 **Strimzi 기반 Kafka Connect 클러스터**의 개념과 구성 원리를 설명합니다.  
Debezium Source Connector와 JDBC Sink Connector의 역할 및 커스텀 플러그인 이미지 빌드 방법을 다룹니다.

---

## 1. Kafka Connect란?

**Kafka Connect**는 Kafka와 외부 시스템(DB, 파일, 클라우드 서비스 등) 사이의 데이터 이동을 담당하는 **프레임워크**입니다.  
별도의 코드 없이 설정(JSON/YAML)만으로 데이터 파이프라인을 구성할 수 있습니다.

```
외부 시스템 (DB, S3, API)
      │
      │   Source Connector
      ▼
  Kafka Topic
      │
      │   Sink Connector
      ▼
외부 시스템 (DB, ElasticSearch, 등)
```

### Source Connector vs Sink Connector

| 종류 | 방향 | 역할 |
|------|------|------|
| Source Connector | 외부 → Kafka | DB 변경 이벤트를 Kafka 토픽으로 전송 |
| Sink Connector | Kafka → 외부 | Kafka 토픽 메시지를 외부 DB에 저장 |

---

## 2. Strimzi에서 Kafka Connect 운영

Strimzi에서는 `KafkaConnect` CR을 통해 Connect 클러스터를 선언적으로 배포합니다.

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnect
metadata:
  annotations:
    strimzi.io/use-connector-resources: "true"   # KafkaConnector CR 사용 활성화
spec:
  bootstrapServers: my-kafka-cluster-kafka-bootstrap:9092
  image: skala-kafka-connect:debezium-3.2.3-kafka-4.0   # 커스텀 플러그인 이미지
```

**`use-connector-resources: "true"` 어노테이션:**
이 설정을 활성화하면 커넥터 등록을 REST API 대신 `KafkaConnector` CR(YAML)로 관리할 수 있습니다.

---

## 3. 왜 커스텀 Docker 이미지가 필요한가?

Strimzi 기본 Kafka 이미지에는 커넥터 플러그인이 포함되어 있지 않습니다.  
Debezium, JDBC 등의 플러그인을 사용하려면 **기본 이미지에 플러그인을 추가한 커스텀 이미지**를 빌드해야 합니다.

```
quay.io/strimzi/kafka:0.48.0-kafka-4.0.0  (Strimzi 기본 이미지)
      │
      │  Dockerfile (플러그인 추가)
      ▼
skala-kafka-connect:debezium-3.2.3-kafka-4.0  (커스텀 이미지)
      │
      ├─ debezium-connector-mysql (MariaDB/MySQL Source)
      ├─ debezium-connector-postgres (PostgreSQL Source)
      ├─ debezium-connector-mongodb (MongoDB Source)
      ├─ debezium-connector-jdbc (JDBC Sink)
      └─ confluentinc-kafka-connect-jdbc (Confluent JDBC Sink)
```

---

## 4. 이번 실습에서 설치하는 플러그인

| 플러그인 | 버전 | 역할 |
|---------|------|------|
| debezium-connector-mysql | 3.2.3.Final | MariaDB/MySQL Binlog Source |
| debezium-connector-postgres | 3.2.3.Final | PostgreSQL WAL Source |
| debezium-connector-mongodb | 3.2.3.Final | MongoDB Change Stream Source |
| debezium-connector-jdbc | 3.2.3.Final | JDBC Sink (Debezium 제공) |
| confluentinc-kafka-connect-jdbc | 10.8.0 | JDBC Sink (Confluent 제공) |
| mysql-connector-java | — | MySQL/MariaDB JDBC 드라이버 |
| postgresql-connector | — | PostgreSQL JDBC 드라이버 |

---

## 5. 두 개의 KafkaConnect 클러스터 설계

이 실습에서는 Source와 Sink 역할을 분리하여 **두 개의 KafkaConnect 클러스터**를 운영합니다.

```
[debezium-source-connect 클러스터]        [jdbc-sink-connect 클러스터]
  group.id: source-connect-cluster          group.id: sink-connect-cluster
  역할: DB 변경 이벤트 수집                 역할: 토픽 메시지를 DB에 저장
  커넥터: Debezium Source Connectors        커넥터: JDBC Sink Connectors
  내부 토픽: source-connect-configs/        내부 토픽: sink-configs/
             source-connect-offsets/                   sink-offsets/
             source-connect-status/                    sink-status/
```

두 클러스터의 `group.id`와 내부 토픽 이름이 달라야 충돌을 방지할 수 있습니다.

---

## 6. Kafka Connect 내부 토픽

Kafka Connect는 상태 관리를 위해 3개의 내부 Kafka 토픽을 사용합니다.

| 토픽 | 용도 |
|------|------|
| config 토픽 | 커넥터 설정 정보 저장 |
| offsets 토픽 | 소스 커넥터의 읽기 위치(오프셋) 저장 |
| status 토픽 | 커넥터 및 태스크 상태 저장 |

---

## 7. MariaDB Binlog 사전 설정

Debezium MySQL/MariaDB Source Connector는 DB의 **Binlog(Binary Log)**를 읽어 변경 이벤트를 감지합니다.

Binlog를 활성화하려면 MariaDB 설정에 다음이 필요합니다:

| 설정 항목 | 필요 값 | 설명 |
|-----------|---------|------|
| `log_bin` | 활성화 | 바이너리 로그 파일 기록 활성화 |
| `binlog_format` | ROW | 행 단위 변경 내용 기록 (STATEMENT 아님) |
| `binlog_row_image` | FULL | 변경 전후 전체 행 기록 |
| `server-id` | 고유한 숫자 | 복제 클러스터에서 고유한 서버 식별자 |

Helm values.yaml을 통한 설정 방법은 `backup/BINLOG_GUIDE.md`를 참조하세요.

---

## 8. 학습 포인트 정리

| 개념 | 핵심 내용 |
|------|-----------|
| Kafka Connect | 코드 없는 데이터 파이프라인 프레임워크 |
| 커스텀 이미지 | 플러그인을 포함한 Strimzi 기반 Docker 이미지 빌드 |
| KafkaConnect CR | Strimzi가 관리하는 Connect 클러스터 선언 |
| use-connector-resources | KafkaConnector CR로 커넥터 등록 활성화 |
| Source/Sink 분리 | 역할별 클러스터 분리로 독립적 설정 및 스케일 관리 |
| Binlog | Debezium이 DB 변경 이벤트를 읽기 위한 MariaDB 설정 |
