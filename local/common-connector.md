# Debezium Connector 공통 설정 필드 가이드

이 문서는 Debezium MySQL/MariaDB 커넥터에서 공통적으로 사용되는 설정 필드에 대한 상세 설명을 제공합니다.

---

## 1. name (커넥터 이름)

### 기본 정보
- **타입**: String
- **필수**: Yes
- **예시**: `"mariadb-outbox-connector"`

### 상세 설명

#### 정의
커넥터 인스턴스를 식별하는 고유한 이름입니다. Kafka Connect 클러스터 내에서 각 커넥터를 구분하는 유일한 식별자로 사용됩니다.

#### 사용 용도
- Kafka Connect REST API에서 커넥터 관리 (조회/삭제/재시작)
- 커넥터 상태 모니터링 및 로그 추적
- 내부 오프셋/상태 저장소의 키로 사용

#### 중복 및 장애 시나리오

##### 시나리오 1: 동일 이름으로 재등록 시도
```bash
# 첫 번째 등록
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{"name": "mariadb-outbox-connector", "config": {...}}'
# 성공

# 같은 이름으로 다시 등록 시도
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{"name": "mariadb-outbox-connector", "config": {...}}'
# 에러: "Connector mariadb-outbox-connector already exists"
```

##### 시나리오 2: 커넥터 장애 후 재적용
```bash
# 커넥터 상태 확인
curl http://localhost:8083/connectors/mariadb-outbox-connector/status
# 상태: FAILED

# 같은 이름으로 재등록 시도
./register-connector.sh mariadb-outbox-connector.json
# 에러: 이미 존재하는 이름
```

### 에러 회피 방법

#### 방법 1: 기존 커넥터 삭제 후 재등록 (권장)
```bash
# 1. 기존 커넥터 삭제
curl -X DELETE http://localhost:8083/connectors/mariadb-outbox-connector

# 또는 스크립트 사용
./delete-connector.sh mariadb-outbox-connector

# 2. 새로 등록
./register-connector.sh mariadb-outbox-connector.json
```

#### 방법 2: 설정 업데이트 (이름 유지)
```bash
# PUT 요청으로 설정 변경
curl -X PUT http://localhost:8083/connectors/mariadb-outbox-connector/config \
  -H "Content-Type: application/json" \
  -d '{"connector.class": "...", "tasks.max": "1", ...}'

# 커넥터 재시작 없이 설정 반영
```

#### 방법 3: 재시작 (이름/설정 유지)
```bash
# 커넥터만 재시작 (설정 변경 없음)
curl -X POST http://localhost:8083/connectors/mariadb-outbox-connector/restart

# FAILED -> RUNNING 전환 시도
```

#### 방법 4: 버전 관리 네이밍 (운영 환경)
```json
{
  "name": "mariadb-outbox-connector-v1.0",
  "config": {...}
}
```

**장점:**
- 롤백 시 이전 버전 유지 가능
- A/B 테스트 가능
- 마이그레이션 시 병렬 운영

**단점:**
- 오프셋/상태 재사용 불가
- 토픽 이름 변경 가능성

### 주의사항

1. **이름 변경 시 영향**
   - 오프셋 정보가 초기화됨 → 스냅샷 재수행
   - 스키마 히스토리 토픽 재생성 필요
   
2. **네이밍 컨벤션**
   - 소문자, 하이픈(-) 사용 권장
   - 의미 있는 이름 (환경, 용도 포함)
   - 예: `prod-mariadb-outbox-connector`, `dev-outbox-cdc`

3. **충돌 방지**
   - 동일 Kafka Connect 클러스터에서 고유해야 함
   - 여러 환경(dev/staging/prod)이 같은 Connect 사용 시 주의

### 실제 운영 예시

```bash
# 개발 환경
{
  "name": "dev-outbox-connector",
  "config": {
    "database.hostname": "dev-mariadb",
    ...
  }
}

# 스테이징 환경
{
  "name": "staging-outbox-connector",
  "config": {
    "database.hostname": "staging-mariadb",
    ...
  }
}

# 프로덕션 환경
{
  "name": "prod-outbox-connector",
  "config": {
    "database.hostname": "prod-mariadb",
    ...
  }
}
```

---

## 2. connector.class

### 기본 정보
- **값**: `io.debezium.connector.mysql.MySqlConnector`
- **필수**: Yes

### 의미
Debezium MySQL/MariaDB 커넥터 클래스를 지정합니다. MariaDB는 MySQL 프로토콜과 호환되므로 MySQL 커넥터를 사용하며, Outbox Pattern은 이 커넥터에 EventRouter SMT(Single Message Transform)를 추가하여 구현합니다.

### 사용 가능한 커넥터 클래스

```json
// MySQL/MariaDB
"connector.class": "io.debezium.connector.mysql.MySqlConnector"

// PostgreSQL
"connector.class": "io.debezium.connector.postgresql.PostgresConnector"

// MongoDB
"connector.class": "io.debezium.connector.mongodb.MongoDbConnector"

// SQL Server
"connector.class": "io.debezium.connector.sqlserver.SqlServerConnector"

// Oracle
"connector.class": "io.debezium.connector.oracle.OracleConnector"
```

---

## 3. tasks.max

### 기본 정보
- **값**: `1`
- **타입**: Integer
- **기본값**: 1

### 상세 설명

**정의**: 커넥터가 실행할 병렬 태스크 수를 지정합니다.

**용도**:
- 여러 테이블 캡처 시 병렬 처리
- 처리량(throughput) 향상

### 설정값에 따른 동작

#### `"tasks.max": "1"` (Outbox 권장)
```json
{
  "name": "mariadb-outbox-connector",
  "config": {
    "tasks.max": "1",
    "table.include.list": "cloud.outbox_events"
  }
}
```

**이유**:
- Outbox는 단일 테이블만 캡처
- 이벤트 순서 보장 중요
- 병렬화 이점 없음

#### `"tasks.max": "3"` (멀티 테이블 CDC)
```json
{
  "name": "mariadb-cdc-connector",
  "config": {
    "tasks.max": "3",
    "table.include.list": "cloud.users,cloud.orders,cloud.products"
  }
}
```

**동작**:
- 3개 테이블을 3개 태스크에 분배
- 각 태스크가 독립적으로 binlog 처리
- 처리량 증가

**주의사항**:
- 태스크 수는 테이블 수를 초과할 수 없음
- 순서 보장이 필요한 경우 단일 태스크 사용

---

## 4. Database 연결 설정

### database.hostname

#### 기본 정보
- **타입**: String
- **필수**: Yes
- **예시**: `"mariadb-cdc"`, `"192.168.1.100"`, `"db.example.com"`

#### 의미
MariaDB 서버의 호스트명 또는 IP 주소입니다.

**환경별 예시**:
```json
// Docker
"database.hostname": "mariadb-cdc"  // 컨테이너명

// Kubernetes
"database.hostname": "mariadb-1.mariadb.svc.cluster.local"  // Service DNS

// Cloud
"database.hostname": "my-db.us-east-1.rds.amazonaws.com"  // RDS 엔드포인트
```

### database.port

#### 기본 정보
- **타입**: String
- **기본값**: `"3306"`
- **필수**: No

#### 의미
MariaDB 서버의 포트 번호입니다.

**비표준 포트 사용**:
```json
"database.port": "3307"  // 커스텀 포트
```

### database.user

#### 기본 정보
- **타입**: String
- **필수**: Yes
- **예시**: `"skala"`, `"cdc_user"`

#### 의미
데이터베이스 접속 계정입니다.

#### 필요 권한

```sql
-- Outbox 전용 권한
GRANT SELECT ON cloud.outbox_events TO 'cdc_user'@'%';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'cdc_user'@'%';
GRANT RELOAD ON *.* TO 'cdc_user'@'%';  -- 스냅샷 시 필요

-- 멀티 테이블 CDC
GRANT SELECT ON cloud.* TO 'cdc_user'@'%';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'cdc_user'@'%';
GRANT RELOAD ON *.* TO 'cdc_user'@'%';

-- 권한 적용
FLUSH PRIVILEGES;
```

**권한 확인**:
```sql
SHOW GRANTS FOR 'cdc_user'@'%';
```

### database.password

#### 기본 정보
- **타입**: String
- **필수**: Yes

#### 의미
데이터베이스 접속 비밀번호입니다.

#### 보안 권장사항

**방법 1: 환경 변수 (Docker)**
```bash
# docker-compose.yaml
environment:
  - DB_PASSWORD=${DB_PASSWORD}

# 커넥터 설정
"database.password": "${env:DB_PASSWORD}"
```

**방법 2: Kubernetes Secret**
```yaml
# secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  password: c2thbGE=  # base64 encoded

# connector.yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: password
```

**방법 3: AWS Secrets Manager**
```json
"database.password": "${secretsmanager:prod/db/password}"
```

### database.connectionTimeZone

#### 기본 정보
- **타입**: String
- **필수**: No
- **예시**: `"Asia/Seoul"`, `"UTC"`

#### 의미
데이터베이스 세션의 타임존을 지정합니다.

**용도**:
- TIMESTAMP 컬럼의 시간대 해석 일관성 보장
- 애플리케이션과 동일한 타임존 사용 권장

**예시**:
```json
// 한국 시간대
"database.connectionTimeZone": "Asia/Seoul"

// UTC (글로벌 서비스)
"database.connectionTimeZone": "UTC"
```

**주의사항**:
```sql
-- 데이터베이스 타임존 확인
SELECT @@system_time_zone, @@session.time_zone;

-- 애플리케이션과 일치시키기
-- Spring Boot application.yaml
spring:
  datasource:
    url: jdbc:mysql://mariadb:3306/cloud?serverTimezone=Asia/Seoul
```

### connect.timeout.ms

#### 기본 정보
- **타입**: Integer
- **기본값**: `30000` (30초)
- **필수**: No

#### 의미
데이터베이스 초기 연결 시 타임아웃 시간(밀리초)입니다.

**용도**:
- 네트워크 지연이 큰 환경(Cloud, VPN)에서 연결 실패 방지
- 느린 네트워크 대응

**환경별 권장값**:
```json
// 로컬 Docker
"connect.timeout.ms": "30000"  // 30초

// Kubernetes (같은 클러스터)
"connect.timeout.ms": "30000"  // 30초

// VPN 통신
"connect.timeout.ms": "60000"  // 60초

// Cross-Region Cloud
"connect.timeout.ms": "90000"  // 90초
```

---

## 참고 자료

- [Debezium MySQL Connector 공식 문서](https://debezium.io/documentation/reference/stable/connectors/mysql.html)
- [Kafka Connect 공식 문서](https://kafka.apache.org/documentation/#connect)
- [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)

---

**문서 버전**: 1.0  
**최종 업데이트**: 2025-11-16
