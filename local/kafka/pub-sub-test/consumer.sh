#!/bin/bash

CLIENT_NAME="kafka-client"
KAFKA_BOOTSTRAP="kafka:9092"
TOPIC_NAME="${1:-test-topic}"

echo "Consumer 시작 - 토픽: ${TOPIC_NAME}"
echo "메시지를 수신합니다 (종료: Ctrl+C):"
echo ""

docker exec -it ${CLIENT_NAME} kafka-console-consumer \
  --topic ${TOPIC_NAME} \
  --from-beginning \
  --bootstrap-server ${KAFKA_BOOTSTRAP}
