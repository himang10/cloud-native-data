#!/bin/bash

# Conduktor 설정
CONTAINER_NAME="conduktor-platform"
IMAGE="conduktor/conduktor-platform:latest"
NETWORK_NAME="kafka-net"
PORT="38080"

# 기존 컨테이너 확인 및 중지/삭제
if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
    echo "기존 Conduktor 컨테이너를 중지하고 삭제합니다..."
    docker stop ${CONTAINER_NAME}
    docker rm ${CONTAINER_NAME}
fi

# 네트워크 확인
if ! docker network inspect ${NETWORK_NAME} &> /dev/null; then
    echo "오류: ${NETWORK_NAME} 네트워크가 없습니다."
    echo "pgvector를 먼저 시작하세요: ./pgvector-run.sh"
    exit 1
fi

# PostgreSQL 컨테이너 실행 확인
if ! docker ps | grep -q pgvector; then
    echo "경고: pgvector 컨테이너가 실행 중이지 않습니다."
    echo "pgvector를 먼저 시작하세요: ./pgvector-run.sh"
    exit 1
fi

echo "Conduktor 컨테이너를 시작합니다..."

# Conduktor 실행
docker run -d \
  --name ${CONTAINER_NAME} \
  --network ${NETWORK_NAME} \
  -p ${PORT}:8080 \
  -e CDK_DATABASE_URL="postgresql://postgres:postgres@pgvector:5432/conduktor" \
  -e CDK_ADMIN_EMAIL="admin@skala.com" \
  -e CDK_ADMIN_PASSWORD="admin" \
  ${IMAGE}

# 컨테이너 시작 대기
echo "Conduktor가 시작될 때까지 대기 중 (약 30초)..."
sleep 30

# 상태 확인
if docker ps | grep -q ${CONTAINER_NAME}; then
    echo ""
    echo "===================================="
    echo "Conduktor가 성공적으로 시작되었습니다!"
    echo "===================================="
    echo ""
    echo "접속 정보:"
    echo "  URL: http://localhost:${PORT}"
    echo "  Admin Email: admin@skala.com"
    echo "  Admin Password: admin"
    echo ""
    echo "초기 설정이 완료될 때까지 1-2분 정도 걸릴 수 있습니다."
    echo ""
    echo "로그 확인:"
    echo "  docker logs -f ${CONTAINER_NAME}"
    echo ""
else
    echo ""
    echo "오류: Conduktor 시작에 실패했습니다."
    echo "로그 확인: docker logs ${CONTAINER_NAME}"
    exit 1
fi
