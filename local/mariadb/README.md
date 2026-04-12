# MariaDB Docker 로컬 환경 스크립트 (Debezium CDC 지원)

Helm Chart values.yaml 설정을 Docker 컨테이너로 실행하는 스크립트 모음입니다.

---

## 목차
1. [run.sh - MariaDB 시작](#runsh)
2. [stop.sh - MariaDB 중지](#stopsh)
3. [logs.sh - 로그 확인](#logssh)
4. [clean.sh - 완전 삭제](#cleansh)
5. [사용 가이드](#사용-가이드)

---

## run.sh

MariaDB 컨테이너를 시작하는 메인 스크립트입니다.

```bash
#!/bin/bash

# MariaDB Docker Container 설정
CONTAINER_NAME="mariadb-cdc"
IMAGE="bitnamilegacy/mariadb:11.4.6-debian-12-r0"
VOLUME_NAME="mariadb-data"
PORT="3306"

# 데이터베이스 설정
MARIADB_ROOT_PASSWORD="Skala25a!23$"
MARIADB_DATABASE="cloud"
MARIADB_USER="skala"
MARIADB_PASSWORD="Skala25a!23$"

# 기존 컨테이너 확인 및 중지/삭제
if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
    echo "기존 컨테이너를 중지하고 삭제합니다..."
    docker stop ${CONTAINER_NAME}
    docker rm ${CONTAINER_NAME}
fi

# 볼륨 생성 (존재하지 않는 경우)
if ! docker volume inspect ${VOLUME_NAME} &> /dev/null; then
    echo "볼륨 ${VOLUME_NAME}을 생성합니다..."
    docker volume create ${VOLUME_NAME}
fi

# MariaDB 설정 파일 생성
cat > /tmp/mariadb-custom.cnf << 'EOF'
[mysqld]
# 기본 설정
skip-name-resolve
explicit_defaults_for_timestamp
max_allowed_packet=16M
bind-address=0.0.0.0
character-set-server=UTF8
collation-server=utf8_general_ci

# Debezium CDC를 위한 Binlog 설정
log-bin=mysql-bin
binlog-format=ROW
binlog-row-image=FULL
server-id=1
expire-logs-days=7
max-binlog-size=100M
binlog-cache-size=32K
transaction-isolation=READ-COMMITTED
sync-binlog=1

[client]
default-character-set=UTF8
EOF

# MariaDB 초기화 SQL 스크립트 생성
cat > /tmp/setup_debezium_user.sql << 'EOF'
-- Debezium CDC 전용 사용자 생성
CREATE USER IF NOT EXISTS 'skala'@'%' IDENTIFIED BY 'Skala25a!23$';

-- Debezium 필수 권한 부여
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT 
ON *.* TO 'skala'@'%';

-- 특정 데이터베이스에 대한 추가 권한
GRANT ALL PRIVILEGES ON cloud.* TO 'skala'@'%';

-- 변경사항 적용
FLUSH PRIVILEGES;
EOF

echo "MariaDB 컨테이너를 시작합니다..."

# Docker 컨테이너 실행
docker run -d \
  --name ${CONTAINER_NAME} \
  -p ${PORT}:3306 \
  -e MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD}" \
  -e MARIADB_DATABASE="${MARIADB_DATABASE}" \
  -e MARIADB_USER="${MARIADB_USER}" \
  -e MARIADB_PASSWORD="${MARIADB_PASSWORD}" \
  -e MARIADB_REPLICATION_USER="${MARIADB_USER}" \
  -e MARIADB_REPLICATION_PASSWORD="${MARIADB_PASSWORD}" \
  -v ${VOLUME_NAME}:/bitnami/mariadb \
  -v /tmp/mariadb-custom.cnf:/opt/bitnami/mariadb/conf/my_custom.cnf:ro \
  -v /tmp/setup_debezium_user.sql:/docker-entrypoint-initdb.d/setup_debezium_user.sql:ro \
  ${IMAGE}

# 컨테이너 시작 대기
echo "MariaDB가 시작될 때까지 대기 중..."
sleep 10

# 상태 확인
if docker ps | grep -q ${CONTAINER_NAME}; then
    echo ""
    echo "===================================="
    echo "MariaDB가 성공적으로 시작되었습니다!"
    echo "===================================="
    echo ""
    echo "접속 정보:"
    echo "  Host: localhost"
    echo "  Port: ${PORT}"
    echo "  Database: ${MARIADB_DATABASE}"
    echo "  Username: ${MARIADB_USER}"
    echo "  Password: ${MARIADB_PASSWORD}"
    echo "  Root Password: ${MARIADB_ROOT_PASSWORD}"
    echo ""
    echo "접속 명령어:"
    echo "  docker exec -it ${CONTAINER_NAME} mysql -u${MARIADB_USER} -p${MARIADB_PASSWORD} ${MARIADB_DATABASE}"
    echo ""
    echo "Binlog 설정 확인:"
    echo "  docker exec -it ${CONTAINER_NAME} mysql -uroot -p${MARIADB_ROOT_PASSWORD} -e \"SHOW VARIABLES LIKE 'log_bin%';\""
    echo ""
    echo "컨테이너 중지:"
    echo "  docker stop ${CONTAINER_NAME}"
    echo ""
    echo "컨테이너 삭제:"
    echo "  docker rm ${CONTAINER_NAME}"
    echo ""
    echo "볼륨 삭제 (데이터 완전 삭제):"
    echo "  docker volume rm ${VOLUME_NAME}"
    echo ""
else
    echo ""
    echo "오류: MariaDB 시작에 실패했습니다."
    echo "로그 확인: docker logs ${CONTAINER_NAME}"
    exit 1
fi
```

---

## stop.sh

MariaDB 컨테이너를 중지하는 스크립트입니다.

```bash
#!/bin/bash

CONTAINER_NAME="mariadb-cdc"

if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    echo "MariaDB 컨테이너를 중지합니다..."
    docker stop ${CONTAINER_NAME}
    echo "컨테이너가 중지되었습니다."
else
    echo "실행 중인 MariaDB 컨테이너가 없습니다."
fi
```

---

## logs.sh

MariaDB 컨테이너의 로그를 확인하는 스크립트입니다.

```bash
#!/bin/bash

CONTAINER_NAME="mariadb-cdc"

if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    echo "MariaDB 로그를 확인합니다 (Ctrl+C로 종료)..."
    echo ""
    docker logs -f ${CONTAINER_NAME}
else
    echo "실행 중인 MariaDB 컨테이너가 없습니다."
    echo ""
    echo "마지막 로그 확인:"
    docker logs ${CONTAINER_NAME} 2>/dev/null || echo "로그가 없습니다."
fi
```

---

## clean.sh

MariaDB 컨테이너와 데이터를 완전히 삭제하는 스크립트입니다.

```bash
#!/bin/bash

CONTAINER_NAME="mariadb-cdc"
VOLUME_NAME="mariadb-data"

echo "경고: 이 스크립트는 MariaDB 컨테이너와 모든 데이터를 삭제합니다."
read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # 컨테이너 중지 및 삭제
    if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
        echo "컨테이너를 중지하고 삭제합니다..."
        docker stop ${CONTAINER_NAME} 2>/dev/null
        docker rm ${CONTAINER_NAME}
        echo "컨테이너가 삭제되었습니다."
    fi
    
    # 볼륨 삭제
    if docker volume inspect ${VOLUME_NAME} &> /dev/null; then
        echo "데이터 볼륨을 삭제합니다..."
        docker volume rm ${VOLUME_NAME}
        echo "볼륨이 삭제되었습니다."
    fi
    
    # 임시 파일 삭제
    rm -f /tmp/mariadb-custom.cnf
    rm -f /tmp/setup_debezium_user.sql
    
    echo ""
    echo "모든 MariaDB 리소스가 삭제되었습니다."
else
    echo "취소되었습니다."
fi
```

---

## 사용 가이드

### 빠른 시작

```bash
# 1. 각 스크립트를 파일로 저장 (run.sh, stop.sh, logs.sh, clean.sh)

# 2. 실행 권한 부여
chmod +x run.sh stop.sh logs.sh clean.sh

# 3. MariaDB 시작
./run.sh

# 4. 접속 테스트
docker exec -it mariadb-cdc mysql -uskala -pSkala25a!23$ cloud
```

### 접속 정보

| 항목 | 값 |
|------|-----|
| Host | localhost |
| Port | 3306 |
| Database | cloud |
| Username | skala |
| Password | Skala25a!23$ |
| Root Password | Skala25a!23$ |

### Debezium CDC 설정

- **Binlog 활성화**: `log-bin=mysql-bin`
- **Binlog Format**: `ROW`
- **Binlog Row Image**: `FULL`
- **Server ID**: 1
- **Binlog 보존 기간**: 7일

### 사용자 권한

Debezium 사용자(skala)는 다음 권한을 가집니다:
- SELECT, RELOAD, SHOW DATABASES
- REPLICATION SLAVE, REPLICATION CLIENT
- cloud 데이터베이스에 대한 ALL PRIVILEGES

### 사용 예제

**1. Binlog 설정 확인**
```bash
docker exec -it mariadb-cdc mysql -uroot -pSkala25a!23$ \
  -e "SHOW VARIABLES LIKE 'log_bin%';"
```

**2. 데이터베이스 접속**
```bash
# 사용자로 접속
docker exec -it mariadb-cdc mysql -uskala -pSkala25a!23$ cloud

# Root로 접속
docker exec -it mariadb-cdc mysql -uroot -pSkala25a!23$
```

**3. 로그 확인**
```bash
./logs.sh
```

**4. 중지**
```bash
./stop.sh
```

**5. 완전 삭제 (데이터 포함)**
```bash
./clean.sh
```

### 데이터 영속성

- 데이터는 Docker Volume `mariadb-data`에 저장됩니다
- 컨테이너를 중지/삭제해도 데이터는 유지됩니다
- 데이터를 완전히 삭제하려면 `clean.sh`를 실행하세요

### 외부 접속

기본적으로 localhost에서만 접속 가능합니다. 외부에서 접속하려면:
- 방화벽/보안그룹에서 3306 포트를 열어야 합니다
- bind-address가 0.0.0.0으로 설정되어 있습니다

### 문제 해결

**포트 충돌**
```bash
# 다른 프로세스가 3306 포트를 사용 중인지 확인
lsof -i :3306
netstat -tulpn | grep 3306
```

**컨테이너 시작 실패**
```bash
# 로그 확인
docker logs mariadb-cdc

# 볼륨 권한 문제시 삭제 후 재시작
./clean.sh
./run.sh
```

### Bitnami Legacy 이미지 관련

- 현재 `bitnamilegacy/mariadb` 이미지를 사용합니다
- **보안 업데이트가 제공되지 않습니다**
- 프로덕션 환경에서는 공식 `mariadb` 이미지 사용을 권장합니다
- Bitnami는 2025년 8월 28일부터 대부분의 이미지를 legacy로 이동했습니다
- bitnamilegacy 이미지는 임시 마이그레이션 용도로만 권장됩니다

### 참고사항

**Helm Chart와의 차이점:**
- Kubernetes의 리소스 제한은 Docker에서 직접 설정 필요
- Prometheus 메트릭 수집은 별도 설정 필요
- ServiceMonitor는 Kubernetes 전용 기능

**추가 설정이 필요한 경우:**
- `run.sh` 파일의 환경 변수 수정
- `/tmp/mariadb-custom.cnf` 설정 조정
- Docker run 명령의 `-m`, `--cpus` 옵션으로 리소스 제한 추가

---

## 라이센스

이 스크립트는 Bitnami MariaDB Helm Chart의 설정을 기반으로 작성되었습니다.
