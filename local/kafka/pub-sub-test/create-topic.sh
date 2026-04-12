#!/bin/bash

CLIENT_NAME="kafka-client"
KAFKA_BOOTSTRAP="kafka:9092"
TOPIC_NAME="${1:-test-topic}"
PARTITIONS="${2:-3}"
REPLICATION_FACTOR="${3:-1}"

echo "토픽 생성: ${TOPIC_NAME}"
echo "  Partitions: ${PARTITIONS}"
echo "  Replication Factor: ${REPLICATION_FACTOR}"
echo ""

docker exec -it ${CLIENT_NAME} kafka-topics \
  --create \
  --topic ${TOPIC_NAME} \
  --bootstrap-server ${KAFKA_BOOTSTRAP} \
  --partitions ${PARTITIONS} \
  --replication-factor ${REPLICATION_FACTOR}

if [ $? -eq 0 ]; then
    echo ""
    echo "토픽 '${TOPIC_NAME}'이 성공적으로 생성되었습니다."
else
    echo ""
    echo "토픽 생성에 실패했습니다."
    exit 1
fi
