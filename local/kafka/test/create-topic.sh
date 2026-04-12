#!/bin/bash

# Bitnami 이미지 사용 시
docker exec -it kafka kafka-topics.sh \
  --create --topic test-topic \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 1
