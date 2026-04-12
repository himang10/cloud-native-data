#!/bin/bash

CLIENT_NAME="kafka-client"
KAFKA_BOOTSTRAP="kafka:9092"
TOPIC_NAME="${1:-test-topic}"

echo "Producer 시작 - 토픽: ${TOPIC_NAME}"
echo "메시지를 입력하세요 (종료: Ctrl+C):"
echo ""

docker exec -it ${CLIENT_NAME} kafka-console-producer \
  --topic ${TOPIC_NAME} \
  --bootstrap-server ${KAFKA_BOOTSTRAP}
