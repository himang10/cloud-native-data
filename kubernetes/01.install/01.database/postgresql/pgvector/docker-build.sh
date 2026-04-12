#!/bin/bash

NAME=postgres
IMAGE_NAME="pgvector"
VERSION="15.2.0-debian-11-r31"
DOCKER_REGISTRY="amdp-registry.skala-ai.com/library"

# 첫 번째 파라미터로 CPU 플랫폼 받기 (기본값: amd64)
CPU_PLATFORM=${1:-amd64}

# arm64가 아닌 경우 amd64로 설정
if [ "${CPU_PLATFORM}" != "arm64" ]; then
    CPU_PLATFORM="amd64"
fi

#IS_CACHE="--no-cache"

# CPU_PLATFORM이 arm64이면 VERSION에 접미사 추가
if [ "${CPU_PLATFORM}" = "arm64" ]; then
    VERSION="${VERSION}-${CPU_PLATFORM}"
fi

echo "================================================"
echo "Debezium Kafka Connect 이미지 빌드"
echo "================================================"
echo "이미지: ${NAME}-${IMAGE_NAME}:${VERSION}"
echo "플랫폼: linux/${CPU_PLATFORM}"
echo "캐시: ${IS_CACHE:-사용}"
echo ""

# Docker 이미지 빌드
docker build \
  --tag ${NAME}-${IMAGE_NAME}:${VERSION} \
  --tag ${DOCKER_REGISTRY}/${NAME}-${IMAGE_NAME}:${VERSION} \
  --tag ${NAME}-${IMAGE_NAME}:latest \
  --file Dockerfile \
  --platform linux/${CPU_PLATFORM} \
  ${IS_CACHE} .

if [ $? -eq 0 ]; then
    echo ""
    echo "Docker 이미지 빌드 완료"
    echo "   - ${NAME}-${IMAGE_NAME}:${VERSION}"
    echo "   - ${DOCKER_REGISTRY}/${NAME}-${IMAGE_NAME}:${VERSION}"
    echo "   - ${NAME}-${IMAGE_NAME}:latest"
    echo "================================================"
else
    echo ""
    echo "Docker 이미지 빌드 실패"
    echo "================================================"
    exit 1
fi
