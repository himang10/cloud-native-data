#!/bin/bash

CLIENT_NAME="kafka-client"
KAFKA_BOOTSTRAP="kafka:9092"

echo "Kafka 토픽 목록:"
echo ""

docker exec -it ${CLIENT_NAME} kafka-topics \
  --list \
  --bootstrap-server ${KAFKA_BOOTSTRAP}
