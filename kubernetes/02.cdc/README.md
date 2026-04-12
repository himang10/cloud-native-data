# CDC 실습 프로젝트

> CDC 개념과 배경 → [WHAT.md](WHAT.md)  
> 단계별 실행 절차 → [TEST-GUIDE.md](TEST-GUIDE.md)

---

## 1. 실습 목표

이 실습은 Debezium 기반 CDC(Change Data Capture)를 Kubernetes 환경에서 직접 구성하고,  
MariaDB의 데이터 변경이 Kafka를 통해 PostgreSQL과 MongoDB로 실시간 동기화되는 전체 파이프라인을 체험하는 것을 목표로 합니다.

| 학습 항목 | 내용 |
|-----------|------|
| KafkaConnector CR 이해 | Strimzi로 Connector를 Kubernetes에 선언적으로 배포하는 방법 |
| Source Connector 구성 | Debezium이 MariaDB Binlog를 읽어 Kafka로 이벤트 전송하는 설정 |
| Sink Connector 구성 | Kafka 이벤트를 PostgreSQL / MongoDB에 자동 저장하는 설정 |
| CDC 파이프라인 검증 | DB에서 변경 → Kafka에서 확인 → 대상 DB에서 동기화 확인 |

---

## 2. 전체 실행 흐름

```
MariaDB (cloud.users / orders / products)
    │
    │  [Binlog 스트리밍]
    ▼
Debezium Source Connector (mariadb-source-cdc-connector-v1.0.3)
    │
    │  [Kafka Topic]
    │  mariadb-cdc.cloud.users
    │  mariadb-cdc.cloud.orders
    │  mariadb-cdc.cloud.products
    ▼
 [PostgreSQL Sink Connector]  [MongoDB Sink Connector]
  UPSERT → cdc_users 등       replaceOne → cdc_users 등
```

---

## 3. 디렉토리 구성

```
02.cdc/
├── WHAT.md                          # CDC 개념 설명
├── README.md                        # 이 파일
├── TEST-GUIDE.md                    # 실습 실행 절차
│
├── mariadb-source-connector.yaml    # Source Connector (MariaDB → Kafka)
├── postgresql-sink-connector.yaml   # Sink Connector (Kafka → PostgreSQL)
├── mongodb-sink-connector.yaml      # Sink Connector (Kafka → MongoDB)
│
└── script/
    ├── check-binlog-status.sh       # MariaDB Binlog 설정 및 권한 검증
    ├── check-connector-status.sh    # Connector 실행 상태 확인
    ├── insert-test-data.sh          # MariaDB 테스트 데이터 삽입/수정/삭제
    └── create-users-table.sh        # users 테이블 초기 생성
```

---

## 4. 구성 요소 설명

### 4.1 mariadb-source-connector.yaml

MariaDB Binlog를 실시간으로 읽어 Kafka로 전송하는 Source Connector입니다.

| 설정 | 값 | 설명 |
|------|----|------|
| `class` | `MySqlConnector` | MariaDB/MySQL용 Debezium Connector |
| `topic.prefix` | `mariadb-cdc` | 생성되는 Topic 접두사 |
| `table.include.list` | `cloud.users, cloud.orders, cloud.products` | 캡처 대상 테이블 |
| `snapshot.mode` | `initial` | 최초 실행 시 기존 데이터 전체 스냅샷 |
| `transforms` | (주석 처리) | CDC Envelope 형식 그대로 전송 |

**생성되는 Kafka Topic:**
```
mariadb-cdc.cloud.users
mariadb-cdc.cloud.orders
mariadb-cdc.cloud.products
```

### 4.2 postgresql-sink-connector.yaml

Kafka Topic의 이벤트를 읽어 PostgreSQL에 UPSERT하는 Sink Connector입니다.

| 설정 | 값 | 설명 |
|------|----|------|
| `class` | `JdbcSinkConnector` | Debezium JDBC Sink |
| `topics.regex` | `mariadb-cdc\.cloud\.(users\|orders\|products)` | 구독할 Topic 패턴 |
| `table.name.format` | `cdc_${source.table}` | 대상 테이블명 (예: `cdc_users`) |
| `insert.mode` | `upsert` | INSERT 또는 UPDATE 자동 처리 |
| `delete.enabled` | `true` | DELETE 이벤트 처리 활성화 |
| `errors.deadletterqueue.topic.name` | `dlq-postgresql-sink` | 처리 실패 메시지 보관 Topic |

### 4.3 mongodb-sink-connector.yaml

동일한 Kafka Topic 이벤트를 읽어 MongoDB 컬렉션에 저장합니다.

| 설정 | 값 | 설명 |
|------|----|------|
| `class` | `MongoDbSinkConnector` | Debezium MongoDB Sink |
| `sink.database` | `cloud` | 대상 MongoDB 데이터베이스 |
| `transforms: route` | `RegexRouter` | Topic명을 컬렉션명으로 변환 (예: `cdc_users`) |

> MongoDB Sink는 CDC Envelope(`before`/`after`/`op`)을 내부적으로 파싱하여,  
> `op=c/u`이면 `replaceOne`, `op=d`이면 `deleteOne`을 수행합니다.

### 4.4 script/check-binlog-status.sh

MariaDB Pod에 접속하여 Binlog 설정과 CDC 사용자 권한을 한 번에 검증합니다.

```bash
./script/check-binlog-status.sh
```

검증 항목:
- `log_bin = ON` : Binlog 활성화 여부
- `binlog_format = ROW` : Debezium 호환 형식
- `binlog_row_image = FULL` : 전체 컬럼 변경 기록
- CDC 사용자(`skala`)의 `REPLICATION SLAVE`, `REPLICATION CLIENT` 권한

### 4.5 script/insert-test-data.sh

MariaDB `cloud.users` 테이블에 INSERT/UPDATE/DELETE 테스트 데이터를 생성합니다.

```bash
./script/insert-test-data.sh insert 3   # 3개 레코드 삽입
./script/insert-test-data.sh update 2   # 최근 2개 업데이트
./script/insert-test-data.sh delete 1   # 최근 1개 삭제
```

---

## 5. 실습을 통해 확인할 수 있는 것

1. MariaDB에 데이터를 INSERT/UPDATE/DELETE 하면 Kafka Topic에 CDC 이벤트가 자동 생성된다.
2. Kafka Topic의 메시지는 Debezium CDC Envelope 형식(`before`/`after`/`op`)을 포함한다.
3. PostgreSQL Sink Connector가 이벤트를 구독하여 `cdc_*` 테이블에 자동으로 반영한다.
4. MongoDB Sink Connector도 동일 이벤트를 구독하여 별도 컬렉션에 저장한다.
5. 하나의 Source DB 변경이 여러 Sink DB로 동시에 전파되는 Multi-Sink 패턴을 확인한다.
