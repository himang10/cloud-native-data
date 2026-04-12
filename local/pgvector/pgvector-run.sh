#!/bin/bash

# PostgreSQL(pgvector) 설정
CONTAINER_NAME="pgvector"
IMAGE="pgvector/pgvector:pg17"
VOLUME_NAME="pgvector-data"
NETWORK_NAME="kafka-net"
PORT="5432"

# 데이터베이스 설정
POSTGRES_PASSWORD="postgres"
POSTGRES_USER="postgres"

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

echo "PostgreSQL(pgvector) 컨테이너를 시작합니다..."

# Docker 컨테이너 실행
docker run -d \
  --name ${CONTAINER_NAME} \
  --network ${NETWORK_NAME} \
  -p ${PORT}:5432 \
  -e POSTGRES_USER="${POSTGRES_USER}" \
  -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  -v ${VOLUME_NAME}:/var/lib/postgresql/data \
  ${IMAGE}

# 컨테이너 시작 대기
echo "PostgreSQL이 시작될 때까지 대기 중..."
sleep 10

# 상태 확인
if docker ps | grep -q ${CONTAINER_NAME}; then
    echo ""
    echo "===================================="
    echo "PostgreSQL이 성공적으로 시작되었습니다!"
    echo "===================================="
    echo ""
    echo "접속 정보:"
    echo "  컨테이너 내부: pgvector:5432 (Conduktor에서)"
    echo "  호스트에서: localhost:${PORT}"
    echo "  네트워크: ${NETWORK_NAME}"
    echo "  Username: ${POSTGRES_USER}"
    echo "  Password: ${POSTGRES_PASSWORD}"
    echo ""
    echo "생성된 데이터베이스:"
    docker exec -it ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -c "\l"
    echo ""
    echo "호스트에서 접속:"
    echo "  psql -h localhost -p ${PORT} -U ${POSTGRES_USER} -d conduktor"
    echo ""
    echo "컨테이너에서 접속:"
    echo "  docker exec -it ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -d conduktor"
    echo ""
    echo "Conduktor 연결 정보:"
    echo "  postgresql://postgres:postgres@pgvector:5432/conduktor"
    echo ""
else
    echo ""
    echo "오류: PostgreSQL 시작에 실패했습니다."
    echo "로그 확인: docker logs ${CONTAINER_NAME}"
    exit 1
fi
