#!/bin/bash

# MariaDB Docker Container 설정
CONTAINER_NAME="mariadb-cdc"
IMAGE="bitnamilegacy/mariadb:11.4.6-debian-12-r0"
VOLUME_NAME="mariadb-data"
NETWORK_NAME="kafka-net"  # ← Kafka와 동일한 네트워크
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

# 네트워크 존재 확인 (없으면 생성)
if ! docker network inspect ${NETWORK_NAME} &> /dev/null; then
    echo "네트워크 ${NETWORK_NAME}이 없습니다. 생성합니다..."
    docker network create ${NETWORK_NAME}
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
  --network ${NETWORK_NAME} \
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
