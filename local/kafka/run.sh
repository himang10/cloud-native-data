#!/bin/bash

CONTAINER_NAME="kafka"
IMAGE="bitnamilegacy/kafka:4.0.0-debian-12-r10"
VOLUME_NAME="kafka-data"
NETWORK_NAME="kafka-net"  # ← 추가

# 기존 컨테이너 확인 및 중지/삭제
if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
    echo "기존 Kafka 컨테이너를 중지하고 삭제합니다..."
    docker stop ${CONTAINER_NAME}
    docker rm ${CONTAINER_NAME}
fi

# 네트워크 생성 (존재하지 않는 경우) ← 추가
if ! docker network inspect ${NETWORK_NAME} &> /dev/null; then
    echo "네트워크 ${NETWORK_NAME}을 생성합니다..."
    docker network create ${NETWORK_NAME}
fi

# Volume 생성 (존재하지 않는 경우)
if ! docker volume inspect ${VOLUME_NAME} &> /dev/null; then
    echo "볼륨 ${VOLUME_NAME}을 생성합니다..."
    docker volume create ${VOLUME_NAME}
fi

echo "Kafka 컨테이너를 시작합니다..."

# Kafka 실행
docker run -d \
  --name ${CONTAINER_NAME} \
  --network ${NETWORK_NAME} \
  -p 9092:9092 \
  -p 29092:29092 \
  -v ${VOLUME_NAME}:/bitnami/kafka \
  -e KAFKA_CFG_NODE_ID=0 \
  -e KAFKA_CFG_PROCESS_ROLES=controller,broker \
  -e KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=0@kafka:9093 \
  -e KAFKA_CFG_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093,EXTERNAL://:29092 \
  -e KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092,EXTERNAL://localhost:29092 \
  -e KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,EXTERNAL:PLAINTEXT \
  -e KAFKA_CFG_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_CFG_INTER_BROKER_LISTENER_NAME=PLAINTEXT \
  -e KAFKA_KRAFT_CLUSTER_ID=abcdefghijk1234567890 \
  ${IMAGE}

# (나머지 동일)
