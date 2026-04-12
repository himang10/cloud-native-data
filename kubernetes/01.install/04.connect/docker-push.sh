#!/bin/bash

NAME=skala
IMAGE_NAME="kafka-connect"
VERSION="debezium-3.2.3-kafka-4.0"
CPU_PLATFORM="amd64"

DOCKER_REGISTRY="amdp-registry.skala-ai.com/library"
DOCKER_REGISTRY_USER="robot\$skala-professor"
DOCKER_REGISTRY_PASSWORD="UNYMp8t89kwIIMwsSmOJJ9d3pMoy14n8"

# CPU_PLATFORM이 arm64이면 VERSION에 접미사 추가
if [ "${CPU_PLATFORM}" = "arm64" ]; then
    VERSION="${VERSION}-${CPU_PLATFORM}"
fi

echo "================================================"
echo "Debezium Kafka Connect 이미지 Push"
echo "================================================"
echo "레지스트리: ${DOCKER_REGISTRY}"
echo "이미지: ${NAME}-${IMAGE_NAME}:${VERSION}"
echo ""

# 1. Docker 레지스트리에 로그인
echo "[1/3] Harbor 레지스트리 로그인 중..."
echo ${DOCKER_REGISTRY_PASSWORD} | docker login ${DOCKER_REGISTRY} \
	-u ${DOCKER_REGISTRY_USER} --password-stdin \
   	|| { echo "❌ Docker 로그인 실패"; exit 1; }

echo "✅ 로그인 성공"
echo ""

# 2. Harbor로 push하기 위해 tag 추가
echo "[2/4] 이미지 태깅 중..."
docker tag ${NAME}-${IMAGE_NAME}:${VERSION} ${DOCKER_REGISTRY}/${NAME}-${IMAGE_NAME}:${VERSION}
docker tag ${NAME}-${IMAGE_NAME}:latest ${DOCKER_REGISTRY}/${NAME}-${IMAGE_NAME}:latest

if [ $? -ne 0 ]; then
    echo "❌ 이미지 태깅 실패"
    exit 1
fi

echo "✅ 태깅 완료"
echo ""

# 3. Docker 이미지 푸시 (버전)
echo "[3/4] 이미지 푸시 중 (${VERSION})..."
docker push ${DOCKER_REGISTRY}/${NAME}-${IMAGE_NAME}:${VERSION}

if [ $? -ne 0 ]; then
    echo "❌ 이미지 푸시 실패 (${VERSION})"
    exit 1
fi

echo "✅ ${VERSION} 푸시 완료"
echo ""

# 4. Docker 이미지 푸시 (latest)
echo "[4/4] 이미지 푸시 중 (latest)..."
docker push ${DOCKER_REGISTRY}/${NAME}-${IMAGE_NAME}:latest

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Docker 이미지 푸시 완료"
    echo "================================================"
    echo ""
    echo "다음 단계:"
    echo "1. KafkaConnect 리소스 배포:"
    echo "   kubectl apply -f kafka-connect-custom.yaml"
    echo ""
    echo "2. 배포 상태 확인:"
    echo "   kubectl get kafkaconnect -n kafka"
    echo "   kubectl describe kafkaconnect debezium-connect-cluster -n kafka"
    echo ""
    echo "3. Pod 확인:"
    echo "   kubectl get pods -n kafka -l strimzi.io/cluster=debezium-connect-cluster"
    echo "================================================"
else
    echo ""
    echo "❌ Docker 이미지 푸시 실패"
    echo "================================================"
    exit 1
fi
