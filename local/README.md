# Kafka Connect Connector 설정 가이드

이 디렉토리는 Debezium 기반 Kafka Connect Connector 설정 및 테스트 환경을 제공합니다.

## 📁 디렉토리 구조

```
local/
├── README.md                           # 이 파일
├── test-cdc-pipeline.sh               # CDC 파이프라인 통합 테스트 스크립트
│
├── outbox-source-connector/           # Outbox Pattern Source Connector
│   ├── README.md
│   ├── mariadb-outbox-connector.json
│   └── *.sh (관리 스크립트)
│
├── kafka-source-connector/            # CDC Source Connector
│   ├── README.md
│   ├── mariadb-source-connector.json
│   └── *.sh (관리 스크립트)
│
├── kafka-sink-connector/              # JDBC Sink Connector
│   ├── README.md
│   ├── postgresql-sink-connector.json
│   └── *.sh (관리 스크립트)
│
├── mariadb/                           # MariaDB 설정 및 스크립트
├── pgvector/                          # PostgreSQL 설정 및 스크립트
├── kafka/                             # Kafka 설정
├── kafka-connect/                     # Kafka Connect 설정
└── conduktor/                         # Conduktor UI 설정
```

---

## 📚 Connector 필드 설정 문서

### 🔵 공통 Connector 필드

모든 Kafka Connect Connector에서 공통으로 사용되는 필드입니다.

| 필드 | 설명 |
|------|------|
| `name` | 커넥터의 고유 식별자. Kafka Connect 클러스터 내에서 유일해야 하며, REST API 및 모니터링에서 사용됨 |
| `connector.class` | 커넥터 구현 클래스의 전체 경로 (예: `io.debezium.connector.mysql.MySqlConnector`, `io.debezium.connector.jdbc.JdbcSinkConnector`) |
| `tasks.max` | 병렬 처리를 위한 최대 Task 수. 높을수록 처리량 증가하지만 리소스 소비도 증가 (권장: CPU 코어 수의 50-75%) |
| `database.hostname` | 연결할 데이터베이스 서버의 호스트명 또는 IP 주소 |
| `database.port` | 데이터베이스 서버의 포트 번호 (MariaDB/MySQL: 3306, PostgreSQL: 5432) |
| `database.user` | 데이터베이스 접속 계정. Source는 REPLICATION 권한, Sink는 INSERT/UPDATE/DELETE 권한 필요 |
| `database.password` | 데이터베이스 접속 비밀번호. 환경변수나 Secret Manager 사용 권장 |

📄 **상세 문서**: [common-connector.md](./common-connector.md)

---

### 🟢 Source Connector 전용 필드

Debezium Source Connector (Outbox, CDC)에서만 사용되는 필드입니다.

#### 1. 스키마 히스토리 설정
DDL 변경 이력을 추적하여 binlog 파싱에 사용합니다.

| 필드 | 설명 |
|------|------|
| `schema.history.internal.kafka.bootstrap.servers` | 스키마 히스토리를 저장할 Kafka 브로커 주소 (예: `localhost:9092`). binlog 재파싱 시 DDL 이력 복원에 사용 |
| `schema.history.internal.kafka.topic` | 스키마 히스토리를 저장하는 Kafka 토픽명. 커넥터별로 고유해야 하며, 삭제하면 스냅샷부터 재시작됨 |
| `schema.history.internal.store.only.captured.tables.ddl` | `true`로 설정 시 `table.include.list`에 명시된 테이블의 DDL만 저장하여 스토리지 절약 |
| `schema.history.internal.skip.unparseable.ddl` | `true`로 설정 시 파싱 불가능한 DDL(저장 프로시저 등)을 무시하고 커넥터 실행 계속 진행 |

📄 **상세 문서**: [source-connector-schema.md](./source-connector-schema.md)

#### 2. Converter 설정
Kafka 메시지 직렬화/역직렬화 형식을 지정합니다.

| 필드 | 설명 |
|------|------|
| `key.converter` | Kafka 메시지 Key의 직렬화 형식. `StringConverter`(문자열), `JsonConverter`(JSON), `AvroConverter`(스키마 레지스트리) 등 선택 가능 |
| `value.converter` | Kafka 메시지 Value의 직렬화 형식. CDC는 `JsonConverter` 권장 (before/after 필드 포함) |
| `value.converter.schemas.enable` | `true`: JSON에 스키마 메타데이터 포함 (Sink 호환성 향상), `false`: 순수 JSON만 전송 (크기 절약) |

📄 **상세 문서**: [common-connector-converters.md](./common-connector-converters.md)

#### 3. Outbox Pattern 전용
EventRouter SMT를 사용한 Outbox 패턴 구현 필드입니다.

| 필드 | 설명 |
|------|------|
| `transforms` | 적용할 SMT(Single Message Transform) 이름. Outbox 패턴에서는 `outbox` 사용 |
| `transforms.outbox.type` | EventRouter SMT 클래스 (`io.debezium.transforms.outbox.EventRouter`). CDC 이벤트를 비즈니스 이벤트로 변환 |
| `transforms.outbox.table.field.event.id` | Outbox 테이블의 이벤트 ID 컬럼명 (예: `id`). 중복 제거 및 추적에 사용 |
| `transforms.outbox.table.field.event.key` | Kafka 메시지 Key로 사용할 컬럼 (예: `aggregate_id`). 파티셔닝 기준이 되며 동일 집합체 이벤트는 순서 보장 |
| `transforms.outbox.table.field.event.type` | 이벤트 타입 컬럼 (예: `event_type`). 토픽 라우팅 또는 Consumer 필터링에 사용 |
| `transforms.outbox.table.field.event.payload` | 비즈니스 데이터가 담긴 페이로드 컬럼 (예: `payload`). JSON 형식 권장 |
| `transforms.outbox.table.expand.json.payload` | `true` 설정 시 JSON 페이로드를 Kafka 메시지 Value로 직접 확장. CDC envelope 제거하여 Consumer 단순화 |
| `transforms.outbox.route.by.field` | 토픽 라우팅에 사용할 컬럼 (예: `aggregate_type`). 값이 `Order`면 `order` 토픽으로 전송 |
| `transforms.outbox.route.topic.replacement` | 토픽 이름 패턴 (예: `${routedByValue}`). 라우팅 필드 값으로 동적 토픽 생성 |

📄 **상세 문서**: [source-connector-transforms.md](./source-connector-transforms.md)

#### 4. CDC Source 전용
표준 CDC 소스 커넥터 전용 필드입니다.

| 필드 | 설명 |
|------|------|
| `database.server.id` | MySQL 복제 클라이언트 고유 ID (1-4294967295). binlog 읽기 시 MySQL 서버가 커넥터를 식별하는 데 사용 |
| `topic.prefix` | 생성되는 Kafka 토픽의 접두어. 최종 토픽명은 `{topic.prefix}.{database}.{table}` 형식 (예: `mariadb-cdc.cloud.users`) |
| `table.include.list` | CDC 캡처 대상 테이블 목록 (형식: `database.table`). 쉼표로 구분하여 여러 테이블 지정 가능 (예: `cloud.users,cloud.orders`) |
| `snapshot.mode` | 초기 스냅샷 모드. `initial`(기존 데이터+CDC), `schema_only`(스키마만), `never`(CDC만), `when_needed`(필요시 자동) |
| `snapshot.locking.mode` | 스냅샷 시 테이블 잠금 방식. `minimal`(짧은 잠금), `none`(잠금 없음, GTID 필요), `extended`(전체 잠금) |
| `max.batch.size` | 한 번에 처리할 binlog 이벤트 수 (기본: 2048). 높으면 처리량 증가하지만 지연시간 늘어남 |
| `max.queue.size` | binlog reader와 Kafka producer 간 내부 큐 크기 (기본: 8192). 급격한 부하 시 버퍼 역할 |

📄 **상세 문서**: 
- [source-connector-outbox.md](./source-connector-outbox.md) (Outbox 전용)
- [source-connector-field-cdc.md](./source-connector-field-cdc.md) (CDC 전용)

---

### 🟡 Sink Connector 전용 필드

JDBC Sink Connector에서만 사용되는 필드입니다.

| 필드 | 설명 |
|------|------|
| `topics.regex` | 구독할 Kafka 토픽의 정규식 패턴 (예: `mariadb-cdc\\.cloud\\..*`). 여러 토픽을 한 번에 구독 가능 |
| `connection.url` | Target 데이터베이스 JDBC URL (예: `jdbc:postgresql://pgvector:5432/cloud`). 프로토콜, 호스트, 포트, DB명 포함 |
| `connection.username` | Target 데이터베이스 접속 계정. INSERT/UPDATE/DELETE 권한 필요 |
| `connection.password` | Target 데이터베이스 접속 비밀번호. 환경변수나 Secret Manager 사용 권장 |
| `table.name.format` | Target 테이블명 생성 패턴 (예: `cdc_${topic}`). `${topic}`은 Kafka 토픽명으로 치환됨 |
| `auto.create` | `true` 설정 시 Target 테이블이 없으면 자동 생성. 프로덕션에서는 `false` 권장 (DDL 명시적 관리) |
| `auto.evolve` | `true` 설정 시 Kafka 스키마 변경 감지 시 Target 테이블 스키마 자동 변경 (ALTER TABLE). 프로덕션 주의 필요 |
| `insert.mode` | 삽입 모드. `insert`(기본), `upsert`(PK 존재 시 UPDATE), `update`(UPDATE만). CDC는 `upsert` 권장 |
| `primary.key.mode` | PK 결정 방식. `record_key`(Kafka Key), `record_value`(메시지 Value의 특정 필드), `none`(PK 없음) |
| `delete.enabled` | `true` 설정 시 Debezium DELETE 이벤트를 Target DB에서도 DELETE 수행. `false`면 무시 |
| `batch.size` | 한 번에 DB에 쓸 레코드 수 (기본: 3000). 높으면 처리량 증가하지만 실패 시 롤백 범위 커짐 |
| `hibernate.c3p0.*` | Hibernate C3P0 연결 풀 설정 (13개 필드). 최소/최대 연결 수, 타임아웃, idle 연결 테스트 등 성능 튜닝 옵션 |
| `errors.retry.delay.max.ms` | 재시도 시 최대 지연 시간 (밀리초). Exponential Backoff의 상한선 (예: 60000 = 1분) |
| `errors.retry.timeout` | 재시도 총 타임아웃 (밀리초). 이 시간 초과 시 DLQ로 전송 또는 실패 처리 (예: 300000 = 5분) |

📄 **상세 문서**: [sink-connector-field-cdc.md](./sink-connector-field-cdc.md)

---

## 🧪 테스트 스크립트

### test-cdc-pipeline.sh

CDC 파이프라인의 전체 흐름을 테스트하는 통합 스크립트입니다.

#### 📋 테스트 흐름

```bash
./test-cdc-pipeline.sh
```

1. **MariaDB 데이터 추가**
   - `users` 테이블에 새 레코드 INSERT
   - 타임스탬프 기반 고유 사용자 생성

2. **CDC 처리 대기**
   - 5초 대기 (Source Connector → Kafka)

3. **Kafka 토픽 확인**
   - `mariadb-cdc.cloud.users` 토픽의 최신 메시지 확인
   - CDC envelope 구조 (before/after/op) 검증

4. **PostgreSQL 동기화 확인**
   - `cdc_users` 테이블 레코드 수 확인
   - 최근 동기화된 데이터 조회

#### 📊 출력 예시

```
====================================
CDC 파이프라인 전체 테스트
====================================

1. MariaDB에 새 사용자 추가...
   ✓ 데이터 추가 완료

2. CDC 처리 대기 중 (5초)...

3. Kafka 토픽의 최신 메시지 확인...
   작업: c, 사용자: test_user_1700121600, 이메일: test@example.com

4. PostgreSQL의 cdc_users 테이블 확인...
 total_rows 
------------
         15
(1 row)

5. PostgreSQL의 최근 데이터 확인...
 id |      username      |      email       |   full_name    
----+--------------------+------------------+----------------
 15 | test_user_1700121600| test@example.com | Test User CDC
(1 row)

====================================
테스트 완료
====================================
```

#### 🔍 추가 확인 명령어

테스트 스크립트가 제공하는 수동 확인 명령어:

```bash
# MariaDB 데이터 확인
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud -e 'SELECT * FROM users;'

# Kafka 토픽 목록
docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list | grep mariadb-cdc

# PostgreSQL 데이터 확인
docker exec pgvector psql -U postgres -d cloud -c 'SELECT * FROM cdc_users;'
```

#### ⚠️ 전제 조건

다음 서비스들이 실행 중이어야 합니다:

1. **MariaDB** (`mariadb-cdc` 컨테이너)
2. **Kafka** (`kafka` 컨테이너)
3. **PostgreSQL** (`pgvector` 컨테이너)
4. **Kafka Connect** (Debezium Source + JDBC Sink)

#### 🚀 빠른 시작

```bash
# 1. 인프라 시작
cd mariadb && ./run.sh
cd ../kafka && ./run.sh
cd ../pgvector && ./run.sh
cd ../kafka-connect && ./run.sh

# 2. Source Connector 등록
cd ../kafka-source-connector
./init-database.sh
./register-connector.sh

# 3. Sink Connector 등록
cd ../kafka-sink-connector
./register-connector.sh

# 4. 테스트 실행
cd ..
./test-cdc-pipeline.sh
```

---

## 📖 커넥터별 상세 가이드

각 디렉토리의 README.md에서 커넥터 관리 방법을 확인하세요:

- **Outbox Source**: [outbox-source-connector/README.md](./outbox-source-connector/README.md)
- **CDC Source**: [kafka-source-connector/README.md](./kafka-source-connector/README.md)
- **JDBC Sink**: [kafka-sink-connector/README.md](./kafka-sink-connector/README.md)

---

## 🔗 참고 자료

- [Debezium 공식 문서](https://debezium.io/documentation/)
- [Kafka Connect 공식 문서](https://kafka.apache.org/documentation/#connect)
- [Confluent JDBC Sink Connector](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/)

---

**문서 버전**: 1.0  
**최종 업데이트**: 2025-11-16
