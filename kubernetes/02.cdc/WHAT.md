# CDC(Change Data Capture)란 무엇인가

## 1. 배경: 왜 CDC가 필요한가

마이크로서비스 환경에서는 동일한 데이터를 여러 서비스가 각자의 데이터베이스에 보관하는 경우가 많습니다.  
예를 들어 MariaDB에 있는 사용자(users) 데이터를 PostgreSQL이나 MongoDB에도 동기화해야 할 때, 전통적인 방식은 다음과 같습니다.

```
전통적인 방식:
애플리케이션 코드 수정 → 변경 시마다 두 DB에 직접 쓰기

문제점:
- 양쪽 DB 쓰기 중 하나가 실패하면 데이터 불일치 발생
- 애플리케이션 코드에 동기화 로직이 침투하여 복잡도 증가
- 실시간성 보장 어려움
```

CDC는 이 문제를 **애플리케이션 코드를 수정하지 않고** 해결합니다.  
데이터베이스 내부의 변경 로그(Binlog)를 읽어 변경사항을 자동으로 전파합니다.

---

## 2. CDC 핵심 개념

### 2.1 Change Data Capture(CDC)

CDC란 데이터베이스에서 발생하는 **행(Row) 수준의 변경 이벤트(INSERT/UPDATE/DELETE)를 실시간으로 감지하여 외부 시스템으로 전달하는 기술**입니다.

```
[MariaDB]  ──Binlog 스트리밍──→  [Debezium]  ──이벤트──→  [Kafka Topic]
           (Slave인 척 접속)                              (Source 역할)
```

MariaDB는 모든 데이터 변경을 Binary Log(Binlog)에 기록합니다.  
Debezium은 마치 MySQL Slave처럼 접속하여 이 Binlog를 읽고, 변경 이벤트를 Kafka Topic으로 전송합니다.

### 2.2 Debezium

Debezium은 오픈소스 CDC 플랫폼입니다.  
MariaDB, PostgreSQL, MongoDB 등 다양한 데이터베이스를 지원하며, Kafka Connector로 실행됩니다.

| 역할 | 설명 |
|------|------|
| Source Connector | DB Binlog를 읽어 Kafka로 이벤트 전송 |
| Sink Connector | Kafka 이벤트를 읽어 대상 DB에 저장 |

### 2.3 Strimzi KafkaConnector

이 실습에서는 Kafka Connect를 Kubernetes에서 운영하기 위해 **Strimzi**를 사용합니다.  
Strimzi를 사용하면 Connector 설정을 Kubernetes의 Custom Resource(CR)로 선언적으로 관리할 수 있습니다.

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: mariadb-source-connector
  labels:
    strimzi.io/cluster: debezium-source-connect  # 어느 KafkaConnect에서 실행할지 지정
spec:
  class: io.debezium.connector.mysql.MySqlConnector
  ...
```

`kubectl apply -f connector.yaml` 명령 하나로 Connector가 배포됩니다.

---

## 3. 전체 처리 흐름

```
MariaDB (users 테이블, INSERT/UPDATE/DELETE)
    │
    │  Binlog 스트리밍 (Slave인 척 접속)
    ▼
Debezium Source Connector
    │
    │  이벤트 전송
    ▼
Kafka Topic: mariadb-cdc.cloud.users (JSON 이벤트)
    │
    │  구독
    ▼
Sink Connector (PostgreSQL / MongoDB)
    - Kafka 이벤트를 읽어 대상 DB에 저장
    - UPSERT / DELETE 자동 처리
```

---

## 4. 주요 개념 설명

### 4.1 Binlog와 ROW 형식

MariaDB CDC가 동작하려면 Binlog가 ROW 형식으로 활성화되어 있어야 합니다.

| 설정 | 필요 값 | 의미 |
|------|---------|------|
| `log_bin` | `ON` | Binary Log 기능 활성화 |
| `binlog_format` | `ROW` | 변경된 행 데이터 자체를 기록 (SQL문이 아님) |
| `binlog_row_image` | `FULL` | 변경 전/후 모든 컬럼 값을 기록 |

> **ROW 형식이 중요한 이유:**  
> `STATEMENT` 형식은 SQL 문장을 기록하므로 비결정론적 함수(`NOW()`, `UUID()`)를 포함하면 복제 결과가 달라질 수 있습니다.  
> `ROW` 형식은 실제 변경된 데이터 값을 기록하므로 항상 정확히 복제됩니다.

### 4.2 스냅샷 모드 (snapshot.mode)

Connector를 처음 배포할 때 기존 데이터를 어떻게 처리할지 결정합니다.

| 모드 | 동작 | 사용 시기 |
|------|------|----------|
| `initial` | 기존 데이터 전체 스냅샷 → 이후 Binlog로 실시간 캡처 | **초기 배포 권장** |
| `schema_only` | 스키마만 캡처, 기존 데이터 무시 | 기존 데이터 불필요 시 |
| `never` | 스냅샷 없이 현재 Binlog 위치부터 캡처 | 이미 동기화된 경우 |

### 4.3 ExtractNewRecordState (SMT Transform)

Debezium이 생성하는 기본 메시지는 `before`/`after`/`op` 필드를 포함한 CDC Envelope 형식입니다.

```json
{
  "before": {"id": 1, "name": "홍길동"},
  "after":  {"id": 1, "name": "홍길동 (수정)"},
  "op":     "u"
}
```

`ExtractNewRecordState` Transform을 적용하면 `after` 값만 추출한 단순한 형식으로 변환됩니다.

```json
{"id": 1, "name": "홍길동 (수정)", "__op": "u", "__ts_ms": 1234567890}
```

Sink Connector(PostgreSQL/MongoDB)는 Transform 적용 여부에 따라 설정이 달라집니다.

### 4.4 Dead Letter Queue (DLQ)

Sink Connector가 메시지를 처리하지 못할 때(스키마 불일치, DB 오류 등) 해당 메시지를 별도 Topic으로 보관합니다.  
DLQ를 설정하면 문제 메시지로 인해 전체 처리가 중단되지 않습니다.

```
정상 메시지 → Sink DB에 저장
실패 메시지 → DLQ Topic(dlq-postgresql-sink)에 저장 → 별도 분석/재처리
```

---

## 5. 이 실습에서 구현하는 내용

| 구성요소 | 역할 |
|----------|------|
| **MariaDB Source Connector** | `cloud.users`, `cloud.orders`, `cloud.products` 변경사항을 Kafka로 전송 |
| **PostgreSQL Sink Connector** | Kafka 이벤트를 받아 PostgreSQL `cdc_users`, `cdc_orders`, `cdc_products` 테이블에 UPSERT |
| **MongoDB Sink Connector** | 동일 Kafka 이벤트를 받아 MongoDB `cdc_users`, `cdc_orders`, `cdc_products` 컬렉션에 저장 |

> 코드 구성과 프로젝트 목표 → [README.md](README.md)  
> 단계별 실행 절차 → [TEST-GUIDE.md](TEST-GUIDE.md)
