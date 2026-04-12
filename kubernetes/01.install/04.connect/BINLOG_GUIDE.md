# MariaDB Binlog 활성화 가이드

**목적**: Debezium CDC를 위한 MariaDB Binary Log (Binlog) 설정

---

## 📋 목차

1. [Binlog란?](#binlog란)
2. [필수 요구사항](#필수-요구사항)
3. [Helm Values 설정](#helm-values-설정)
4. [사용자 권한 설정](#사용자-권한-설정)
5. [Helm Upgrade 실행](#helm-upgrade-실행)
6. [설정 확인](#설정-확인)
7. [문제 해결](#문제-해결)

---

## Binlog란?

**Binary Log (Binlog)**는 MariaDB/MySQL의 모든 데이터 변경 사항(INSERT, UPDATE, DELETE)을 기록하는 로그입니다.

### CDC에서 Binlog가 필요한 이유

- **실시간 변경 추적**: 데이터베이스의 모든 변경사항을 실시간으로 캡처
- **순서 보장**: 변경 순서대로 이벤트 발생
- **최소 성능 영향**: 스냅샷 방식보다 효율적

---

## 필수 요구사항

Debezium CDC를 위한 MariaDB Binlog 필수 설정:

| 설정 | 값 | 설명 |
|-----|---|------|
| `log_bin` | `mysql-bin` | Binlog 활성화 |
| `binlog_format` | `ROW` | Row 단위 복제 (필수) |
| `binlog_row_image` | `FULL` | 전체 행 데이터 기록 |
| `server-id` | `1` (고유값) | 서버 식별자 |
| `expire_logs_days` | `7-10` | Binlog 보존 기간 |

---

## Helm Values 설정

### 1. Bitnami MariaDB Helm Chart용 설정

`mariadb-custom-values.yaml` 파일 생성:

```yaml
# MariaDB Helm Chart values.yaml 구성 (Debezium CDC 지원)
## 전역 설정
global:
  storageClass: "gp2"
  security:
    allowInsecureImages: true

## 이미지 설정
image:
  registry: docker.io
  repository: bitnamilegacy/mariadb
  tag: "11.4.6-debian-12-r0"
  pullPolicy: IfNotPresent

## MariaDB 기본 설정
auth:
  rootPassword: "Skala25a!23$"
  database: "cloud"
  username: "skala"
  password: "Skala25a!23$"
  replicationUser: "skala"
  replicationPassword: "Skala25a!23$"

## 🔥 Primary 인스턴스 설정 (중요!)
primary:
  # 리소스 설정
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 500m
      memory: 512Mi
  
  # 퍼시스턴트 볼륨 설정
  persistence:
    enabled: true
    storageClass: "gp2"
    accessModes:
      - ReadWriteOnce
    size: 20Gi
  
  # 서비스 설정
  service:
    type: ClusterIP
    ports:
      mysql: 3306
  
  # 🔥🔥🔥 중요: Primary 전용 설정 (Debezium CDC 필수)
  configuration: |
    [mysqld]
    skip-name-resolve
    explicit_defaults_for_timestamp
    basedir=/opt/bitnami/mariadb
    plugin_dir=/opt/bitnami/mariadb/plugin
    port=3306
    socket=/opt/bitnami/mariadb/tmp/mysql.sock
    tmpdir=/opt/bitnami/mariadb/tmp
    max_allowed_packet=16M
    bind-address=*
    pid-file=/opt/bitnami/mariadb/tmp/mysqld.pid
    log-error=/opt/bitnami/mariadb/logs/mysqld.log
    character-set-server=UTF8
    collation-server=utf8_general_ci
    slow_query_log=0
    long_query_time=10.0
    
    # ==========================================
    # 🔥 Debezium CDC를 위한 Binlog 설정
    # ==========================================
    
    # 필수: Binlog 활성화
    log-bin=mysql-bin
    
    # 필수: Row 기반 복제 형식
    binlog-format=ROW
    
    # 필수: 전체 행 이미지 기록
    binlog-row-image=FULL
    
    # 필수: 고유한 서버 ID
    server-id=1
    
    # 권장: Binlog 보존 기간 (일 단위)
    expire-logs-days=7
    
    # 권장: Binlog 최대 파일 크기
    max-binlog-size=100M
    
    # 선택: Binlog 캐시 크기
    binlog-cache-size=32K
    
    # 선택: 트랜잭션 격리 수준
    transaction-isolation=READ-COMMITTED
    
    # 권장: 동기화 설정
    sync-binlog=1
    
    # ==========================================
    
    [client]
    port=3306
    socket=/opt/bitnami/mariadb/tmp/mysql.sock
    default-character-set=UTF8
    plugin_dir=/opt/bitnami/mariadb/plugin
    
    [manager]
    port=3306
    socket=/opt/bitnami/mariadb/tmp/mysql.sock
    pid-file=/opt/bitnami/mariadb/tmp/mysqld.pid

## Secondary 인스턴스 설정
secondary:
  replicaCount: 0  # Standalone 모드이므로 0

## 아키텍처 설정
architecture: standalone

## 메트릭 설정
metrics:
  enabled: true
  image:
    registry: docker.io
    repository: bitnamilegacy/mysqld-exporter
    tag: "0.15.1-debian-12-r28"
    pullPolicy: IfNotPresent
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 50m
      memory: 64Mi
  serviceMonitor:
    enabled: false
  prometheusRule:
    enabled: false

## 볼륨 권한 설정
volumePermissions:
  enabled: true
  image:
    registry: docker.io
    repository: bitnamilegacy/os-shell
    tag: "12-debian-12-r43"
    pullPolicy: IfNotPresent
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 50m
      memory: 64Mi

## 초기화 스크립트 - Debezium 사용자 생성
initdbScripts:
  setup_debezium_user.sql: |
    -- Debezium CDC 전용 사용자 생성
    CREATE USER IF NOT EXISTS 'skala'@'%' IDENTIFIED BY 'Skala25a!23$';
    
    -- Debezium 필수 권한 부여
    GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT 
    ON *.* TO 'skala'@'%';
    
    -- 권한 확인
    SHOW GRANTS FOR 'skala'@'%';

    -- 특정 데이터베이스에 대한 추가 권한
    GRANT ALL PRIVILEGES ON cloud.* TO 'skala'@'%';
    
    -- 변경사항 적용
    FLUSH PRIVILEGES;

## 네트워크 정책
networkPolicy:
  enabled: false
  allowExternal: true

## 보안 컨텍스트
podSecurityContext:
  enabled: true
  fsGroup: 1001

containerSecurityContext:
  enabled: true
  runAsUser: 1001
  runAsNonRoot: true

## 환경 변수
extraEnvVars:
  - name: MARIADB_EXTRA_FLAGS
    value: "--log-bin=mysql-bin --binlog-format=ROW --server-id=1"
```

### ⚠️ 주의사항

1. **`configuration` 위치**: 반드시 `primary.configuration` 아래에 배치해야 합니다!
2. **들여쓰기**: YAML 들여쓰기를 정확히 지켜야 합니다.
3. **server-id**: 여러 MariaDB 인스턴스가 있는 경우 각각 고유한 값 사용

---

## 사용자 권한 설정

### Debezium CDC에 필요한 권한

```sql
-- CDC 사용자 생성 (skala 사용자 사용)
CREATE USER IF NOT EXISTS 'skala'@'%' IDENTIFIED BY 'Skala25a!23$';

-- 필수 권한 부여
GRANT SELECT                  -- 데이터 읽기
     ,RELOAD                  -- Binlog 읽기
     ,SHOW DATABASES          -- 데이터베이스 목록
     ,REPLICATION SLAVE       -- Binlog 복제
     ,REPLICATION CLIENT      -- 복제 상태 확인
ON *.* TO 'skala'@'%';

-- 특정 데이터베이스 권한
GRANT ALL PRIVILEGES ON cloud.* TO 'skala'@'%';

-- 변경사항 적용
FLUSH PRIVILEGES;
```

### 기존 사용자에게 권한 추가

```sql
-- 기존 사용자 (예: skala)에게 CDC 권한 추가
GRANT RELOAD, REPLICATION SLAVE, REPLICATION CLIENT 
ON *.* TO 'skala'@'%';

FLUSH PRIVILEGES;

-- 권한 확인
SHOW GRANTS FOR 'skala'@'%';
```

---

## Helm Upgrade 실행

### 1. 기존 Release 확인

```bash
# Helm release 목록 확인
helm list -n mariadb

# 현재 설정 확인
helm get values mariadb-1 -n mariadb
```

### 2. Dry-run으로 검증

```bash
# 실제 적용 전 검증
helm upgrade mariadb-1 bitnami/mariadb \
  -n mariadb \
  -f mariadb-custom-values.yaml \
  --dry-run --debug
```

### 3. Helm Upgrade 실행

```bash
# MariaDB Helm Chart 업그레이드
helm upgrade mariadb-1 bitnami/mariadb \
  -n mariadb \
  -f mariadb-custom-values.yaml

# 또는 기존 values 유지하면서 업그레이드
helm upgrade mariadb-1 bitnami/mariadb \
  -n mariadb \
  -f mariadb-custom-values.yaml \
  --reuse-values
```

### 4. Pod 재시작 확인

```bash
# Pod 상태 확인
kubectl get pods -n mariadb -w

# Pod가 Running 상태가 될 때까지 대기
# 예상 시간: 2-3분
```

---

## 설정 확인

### 1. Binlog 설정 확인

```bash
# MariaDB Pod에 접속하여 Binlog 설정 확인
kubectl exec -n mariadb mariadb-1-0 -c mariadb -- \
  mysql -u root -p'Skala25a!23$' -e \
  "SHOW VARIABLES LIKE 'binlog_format'; 
   SHOW VARIABLES LIKE 'log_bin'; 
   SHOW VARIABLES LIKE 'server_id';
   SHOW VARIABLES LIKE 'binlog_row_image';"
```

**예상 결과**:
```
+------------------+-------+
| Variable_name    | Value |
+------------------+-------+
| binlog_format    | ROW   | ✅
| log_bin          | ON    | ✅
| server_id        | 1     | ✅
| binlog_row_image | FULL  | ✅
+------------------+-------+
```

### 2. Binlog 파일 확인

```bash
# Binlog 파일 목록 확인
kubectl exec -n mariadb mariadb-1-0 -c mariadb -- \
  mysql -u root -p'Skala25a!23$' -e "SHOW BINARY LOGS;"
```

**예상 결과**:
```
+------------------+-----------+
| Log_name         | File_size |
+------------------+-----------+
| mysql-bin.000001 |       354 |
| mysql-bin.000002 |      1234 |
+------------------+-----------+
```

### 3. Master 상태 확인

```bash
# Master 상태 및 현재 Binlog 위치 확인
kubectl exec -n mariadb mariadb-1-0 -c mariadb -- \
  mysql -u root -p'Skala25a!23$' -e "SHOW MASTER STATUS;"
```

**예상 결과**:
```
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| mysql-bin.000002 |      659 |              |                  |
+------------------+----------+--------------+------------------+
```

### 4. 사용자 권한 확인

```bash
# CDC 사용자 권한 확인
kubectl exec -n mariadb mariadb-1-0 -c mariadb -- \
  mysql -u root -p'Skala25a!23$' -e "SHOW GRANTS FOR 'skala'@'%';"
```

**예상 결과**:
```
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, BINLOG MONITOR 
ON *.* TO 'skala'@'%' IDENTIFIED BY PASSWORD '...'
GRANT ALL PRIVILEGES ON `cloud`.* TO 'skala'@'%'
```

---

## 문제 해결

### ❌ 문제 1: Binlog가 활성화되지 않음

**증상**:
```
binlog_format | STATEMENT
log_bin       | OFF
```

**원인**: `configuration` 블록이 `primary` 아래에 없음

**해결**:
```yaml
# ❌ 잘못된 위치
configuration: |
  [mysqld]
  log_bin=mysql-bin

# ✅ 올바른 위치
primary:
  configuration: |
    [mysqld]
    log_bin=mysql-bin
```

### ❌ 문제 2: 권한 부족 에러

**증상**:
```
Access denied; you need (at least one of) the RELOAD privilege(s)
```

**해결**:
```bash
kubectl exec -n mariadb mariadb-1-0 -c mariadb -- \
  mysql -u root -p'Skala25a!23$' -e \
  "GRANT RELOAD, REPLICATION SLAVE ON *.* TO 'skala'@'%'; FLUSH PRIVILEGES;"
```

### ❌ 문제 3: Debezium 에러 - ROW format 필요

**증상**:
```
The MySQL server is not configured to use a ROW binlog_format
```

**해결**:
1. Helm values에 `binlog_format=ROW` 추가
2. Helm upgrade 실행
3. Pod 재시작 대기
4. 설정 확인

### ❌ 문제 4: Pod가 재시작되지 않음

**해결**:
```bash
# Pod 강제 재시작
kubectl delete pod mariadb-1-0 -n mariadb

# 새 Pod가 Running 상태가 될 때까지 대기
kubectl get pods -n mariadb -w
```

---

## 📚 추가 리소스

### Binlog 설정 최적화

#### 프로덕션 환경 권장 설정

```ini
[mysqld]
# 성능 최적화
binlog-cache-size=32K            # 트랜잭션 캐시 크기
binlog-stmt-cache-size=32K       # Statement 캐시 크기
max-binlog-size=1G               # 1GB (큰 트랜잭션 처리)
sync-binlog=1                    # 안전성 (성능 영향 있음)

# 디스크 관리
expire-logs-days=10              # 10일 후 자동 삭제
max-binlog-files=10              # 최대 파일 개수

# GTID 모드 (권장)
gtid-strict-mode=ON
log-slave-updates=ON
```

#### 개발 환경 최소 설정

```ini
[mysqld]
log-bin=mysql-bin
binlog-format=ROW
binlog-row-image=FULL
server-id=1
expire-logs-days=3
```

### Binlog 수동 관리

#### Binlog 파일 정리

```sql
-- 특정 날짜 이전 Binlog 삭제
PURGE BINARY LOGS BEFORE '2025-10-15 00:00:00';

-- 특정 파일까지 삭제
PURGE BINARY LOGS TO 'mysql-bin.000010';

-- 모든 Binlog 삭제 (주의!)
RESET MASTER;
```

#### Binlog 읽기

```bash
# Binlog 내용 확인 (MariaDB Pod 내부)
mysqlbinlog /opt/bitnami/mariadb/data/mysql-bin.000001

# 특정 시간 범위만 확인
mysqlbinlog --start-datetime="2025-10-22 00:00:00" \
            --stop-datetime="2025-10-22 23:59:59" \
            /opt/bitnami/mariadb/data/mysql-bin.000001
```

---

## ✅ 체크리스트

MariaDB Binlog 설정 완료 확인:

- [ ] Helm values 파일에 `primary.configuration` 블록 추가
- [ ] `binlog_format=ROW` 설정 추가
- [ ] `log_bin=mysql-bin` 설정 추가
- [ ] `server-id` 고유값 설정
- [ ] Helm upgrade 실행
- [ ] Pod가 정상적으로 재시작됨
- [ ] `SHOW VARIABLES LIKE 'binlog_format'` → **ROW** 확인
- [ ] `SHOW VARIABLES LIKE 'log_bin'` → **ON** 확인
- [ ] CDC 사용자 권한 설정 (RELOAD, REPLICATION SLAVE)
- [ ] `SHOW BINARY LOGS` 명령어로 Binlog 파일 생성 확인
- [ ] Debezium Connector 배포 및 RUNNING 상태 확인
- [ ] 테스트 데이터 INSERT/UPDATE/DELETE 후 Kafka Topic에 메시지 확인

---

## 🎯 다음 단계

Binlog 설정 완료 후:

1. **Debezium Connector 배포**
   ```bash
   kubectl apply -f mariadb-source-connector-cdc.yaml
   ```

2. **Connector 상태 확인**
   ```bash
   kubectl get kafkaconnector -n kafka
   ```

3. **CDC 동작 테스트**
   ```bash
   # 데이터 삽입
   INSERT INTO users (...) VALUES (...);
   
   # Kafka Topic 확인
   kubectl exec -n kafka my-kafka-cluster-kafka-pool-0 -- \
     bin/kafka-console-consumer.sh \
     --bootstrap-server localhost:9092 \
     --topic mariadb.cloud.users \
     --from-beginning
   ```

---

## 📞 참고

- **Debezium 공식 문서**: https://debezium.io/documentation/reference/stable/connectors/mysql.html
- **MariaDB Binlog 문서**: https://mariadb.com/kb/en/binary-log/
- **Bitnami MariaDB Helm Chart**: https://github.com/bitnami/charts/tree/main/bitnami/mariadb

---

**작성일**: 2025년 10월 22일  
**버전**: 1.0  
**테스트 환경**: Bitnami MariaDB 11.4.6, Debezium 2.4.0

