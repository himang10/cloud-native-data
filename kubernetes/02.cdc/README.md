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

### 2.1 개요 흐름

```
┌─────────────────────────────────────────────┐
  MariaDB (DB: cloud)                        
  ├── cloud.users                            
  ├── cloud.orders                           
  └── cloud.products                         
└────────────────┬────────────────────────────┘
                 │ Binlog (ROW 포맷)
                 ▼
┌─────────────────────────────────────────────┐
  Debezium Source Connector                  
  (mariadb-source-cdc-connector-v1.0.0)      
                                             
  table.include.list: cloud.users, ...    ──────→ 캡처 대상 테이블 지정
  topic.prefix: mariadb-cdc               ──────→ Topic 이름 접두사
  snapshot.mode: initial                  ──────→ 최초 전체 데이터 동기화
  transforms: (없음)                       ──────→ Envelope 형식 그대로 전송
└────────────────┬────────────────────────────┘
                 │ Kafka CDC Envelope 메시지
                 │ Key:   { "id": 1 }           ← PK 자동 매핑
                 │ Value: { before, after,       ← 변경 전/후 데이터
                 │          source, op, ts_ms }  ← 메타데이터 + 이벤트 유형
                 ▼
┌─────────────────────────────────────────────┐
  Kafka Topics                               
                                             
  mariadb-cdc.cloud.users    ← cloud.users   
  mariadb-cdc.cloud.orders   ← cloud.orders  
  mariadb-cdc.cloud.products ← cloud.products
                                             
  Topic 이름 규칙: {topic.prefix}.{db}.{table}
└──────────┬──────────────────┬───────────────┘
           │                  │
           ▼                  ▼
┌──────────────────┐  ┌──────────────────────┐
  PostgreSQL Sink         MongoDB Sink        
  Connector               Connector           
                                        
                                          
  table.name.format       transforms: route    
   cdc_${source.           RegexRouter:        
   table}                  mariadb-cdc.cloud.* 
                           → cdc_*             
  insert.mode: upsert     
                          op=c/u → replaceOne  
  primary.key.mode:       op=d   → deleteOne   
   record_key                              
  delete.enabled:                          
   true                                    
└──────────┬───────┘  └──────────┬───────────┘
           │                     │
           ▼                     ▼
┌──────────────────┐  ┌──────────────────────┐
   PostgreSQL              MongoDB             
   (DB: cloud)            (DB: cloud)         
                                          
   cdc_users               cdc_users           
   cdc_orders              cdc_orders          
   cdc_products            cdc_products        
└──────────────────┘  └──────────────────────┘
```

### 2.2 테이블 → Topic → 대상 테이블 매핑

| MariaDB 테이블 | Kafka Topic | PostgreSQL 테이블 | MongoDB 컬렉션 |
|----------------|-------------|-------------------|----------------|
| `cloud.users` | `mariadb-cdc.cloud.users` | `cdc_users` | `cdc_users` |
| `cloud.orders` | `mariadb-cdc.cloud.orders` | `cdc_orders` | `cdc_orders` |
| `cloud.products` | `mariadb-cdc.cloud.products` | `cdc_products` | `cdc_products` |

**Topic 이름 생성 규칙 (Source):**
```
{topic.prefix} . {database.include.list} . {table}
   mariadb-cdc  .         cloud          .  users
                    = mariadb-cdc.cloud.users
```

**대상 테이블명 생성 규칙 (PostgreSQL Sink):**
```
table.name.format: cdc_${source.table}
  source.table = users  →  cdc_users
```

**대상 컬렉션명 생성 규칙 (MongoDB Sink):**
```
transforms.route.regex:       mariadb-cdc\.cloud\.(.*)
transforms.route.replacement: cdc_$1
  mariadb-cdc.cloud.users  →  cdc_users
```

### 2.3 이벤트 유형별 처리 흐름

| MariaDB 작업 | Kafka `op` 값 | PostgreSQL 처리 | MongoDB 처리 |
|--------------|--------------|-----------------|--------------|
| INSERT | `c` (create) | `INSERT ON CONFLICT UPDATE` (upsert) | `replaceOne` (upsert) |
| UPDATE | `u` (update) | `INSERT ON CONFLICT UPDATE` (upsert) | `replaceOne` (upsert) |
| DELETE | `d` (delete) | `DELETE WHERE pk = key` | `deleteOne` |
| 스냅샷 | `r` (read) | `INSERT ON CONFLICT UPDATE` (upsert) | `replaceOne` (upsert) |

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

## 5. CDC Envelope 구조와 unwrap Transform

### 5.1 기본 Envelope 구조 (현재 설정)

Debezium은 기본적으로 Kafka 메시지를 **Envelope 형식**으로 전송합니다.  
현재 `mariadb-source-connector.yaml`에서 `transforms`가 주석 처리되어 있으므로 이 형식이 사용됩니다.

**Kafka Message Key** (테이블 Primary Key 자동 매핑):
```json
{
  "schema": { ... },
  "payload": { "id": 1 }
}
```

**Kafka Message Value** (Envelope 구조):
```json
{
  "before": null,
  "after": { "id": 1, "name": "Alice", "email": "a@a.com" },
  "source": {
    "db": "cloud",
    "table": "users",
    "ts_ms": 1712345678000
  },
  "op": "c",
  "ts_ms": 1712345678123
}
```

| 필드 | 설명 |
|------|------|
| `before` | 변경 이전 row 값 (INSERT 시 `null`) |
| `after` | 변경 이후 row 값 (DELETE 시 `null`) |
| `source` | 이벤트 출처 메타데이터 (DB명, 테이블명, 바이너리로그 위치 등) |
| `op` | 이벤트 유형: `c`(INSERT), `u`(UPDATE), `d`(DELETE), `r`(스냅샷) |
| `ts_ms` | Debezium이 이벤트를 처리한 시각 (epoch ms) |

**Sink 처리 방식:**
- `JdbcSinkConnector` (PostgreSQL): Envelope을 네이티브로 파싱 → `op=c/u`이면 UPSERT, `op=d`이면 DELETE
- `MongoDbSinkConnector` (MongoDB): Envelope을 내부적으로 파싱 → `op=c/u`이면 `replaceOne`, `op=d`이면 `deleteOne`

---

### 5.2 unwrap Transform (ExtractNewRecordState) 적용 시

`transforms: unwrap`을 활성화하면 Source가 Kafka로 보내기 전에 **Envelope을 제거하고 평탄화**합니다.

**mariadb-source-connector.yaml** — unwrap 활성화 예시:
```yaml
transforms: unwrap
transforms.unwrap.type: io.debezium.transforms.ExtractNewRecordState
transforms.unwrap.add.fields: op,ts_ms,db,table
transforms.unwrap.drop.tombstones: false
transforms.unwrap.delete.handling.mode: none
```

**unwrap 적용 후 Kafka Message Value:**
```json
{
  "id": 1,
  "name": "Alice",
  "email": "a@a.com",
  "__op": "c",
  "__ts_ms": 1712345678123,
  "__db": "cloud",
  "__table": "users"
}
```

> Envelope의 `before`/`after` 계층이 사라지고, `after` 값이 최상위로 올라옵니다.  
> `add.fields`에 지정한 메타데이터는 `__` 접두사로 추가됩니다.

**unwrap 적용 시 Sink 변경 영향:**

| 항목 | Envelope 모드 (현재) | unwrap 모드 |
|------|----------------------|-------------|
| PostgreSQL (`JdbcSinkConnector`) | Envelope 네이티브 파싱, DELETE 자동 처리 | `op` 인식 불가, DELETE 처리 복잡 |
| MongoDB (`MongoDbSinkConnector`) | Envelope 네이티브 파싱, `replaceOne`/`deleteOne` 자동 처리 | 별도 파싱 로직 필요 |
| 적합한 Sink | Debezium JDBC / MongoDB Sink | Elasticsearch, S3, 단순 저장소 |

> **권장:** `JdbcSinkConnector`와 `MongoDbSinkConnector`는 Envelope 모드에 최적화되어 있습니다.  
> unwrap은 Debezium 전용 Sink가 아닌 범용 저장소(Elasticsearch, S3 등)에 연동할 때 사용하세요.

---

## 6. 실습을 통해 확인할 수 있는 것

1. MariaDB에 데이터를 INSERT/UPDATE/DELETE 하면 Kafka Topic에 CDC 이벤트가 자동 생성된다.
2. Kafka Topic의 메시지는 Debezium CDC Envelope 형식(`before`/`after`/`op`)을 포함한다.
3. PostgreSQL Sink Connector가 이벤트를 구독하여 `cdc_*` 테이블에 자동으로 반영한다.
4. MongoDB Sink Connector도 동일 이벤트를 구독하여 별도 컬렉션에 저장한다.
5. 하나의 Source DB 변경이 여러 Sink DB로 동시에 전파되는 Multi-Sink 패턴을 확인한다.
