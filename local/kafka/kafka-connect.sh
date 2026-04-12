#!/usr/bin/env bash
set -eux

# ===== 설정 =====
NETWORK_NAME="kafka-net"
CONNECT_CONTAINER_NAME="kafka-connect"
CONNECT_REST_PORT=8083
BROKER_BOOTSTRAP_INTERNAL="kafka:9092"   # 컨테이너 내부에서 접속 (kafka-net 기준)
IMAGE="amdp-registry.skala-ai.com/library/skala-kafka-connect:debezium-3.2.3-kafka-4.0"

# Kafka Connect 내부 토픽/그룹 (질문 YAML과 동일)
GROUP_ID="source-connect-cluster"
CONFIG_TOPIC="source-connect-configs"
OFFSET_TOPIC="source-connect-offsets"
STATUS_TOPIC="source-connect-status"

# JVM 메모리
HEAP_OPTS="-Xms1g -Xmx1g"

# ===== 네트워크 확인/생성 =====
if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
  echo ">> creating docker network: ${NETWORK_NAME}"
  docker network create "${NETWORK_NAME}"
else
  echo ">> docker network exists: ${NETWORK_NAME}"
fi

# ===== 기존 컨테이너 정리 =====
if docker ps -a --format '{{.Names}}' | grep -q "^${CONNECT_CONTAINER_NAME}$"; then
  echo ">> removing existing container: ${CONNECT_CONTAINER_NAME}"
  docker rm -f "${CONNECT_CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

# ===== Kafka Connect 기동 =====
echo ">> starting Kafka Connect (${CONNECT_CONTAINER_NAME})"
docker run -d --name "${CONNECT_CONTAINER_NAME}" \
  --network "${NETWORK_NAME}" \
  -p ${CONNECT_REST_PORT}:8083 \
  -e CONNECT_BOOTSTRAP_SERVERS="${BROKER_BOOTSTRAP_INTERNAL}" \
  -e CONNECT_GROUP_ID="${GROUP_ID}" \
  -e CONNECT_CONFIG_STORAGE_TOPIC="${CONFIG_TOPIC}" \
  -e CONNECT_OFFSET_STORAGE_TOPIC="${OFFSET_TOPIC}" \
  -e CONNECT_STATUS_STORAGE_TOPIC="${STATUS_TOPIC}" \
  -e CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR=1 \
  -e CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR=1 \
  -e CONNECT_STATUS_STORAGE_REPLICATION_FACTOR=1 \
  \
  -e CONNECT_KEY_CONVERTER=org.apache.kafka.connect.json.JsonConverter \
  -e CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE=true \
  -e CONNECT_VALUE_CONVERTER=org.apache.kafka.connect.json.JsonConverter \
  -e CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE=true \
  \
  -e CONNECT_INTERNAL_KEY_CONVERTER=org.apache.kafka.connect.json.JsonConverter \
  -e CONNECT_INTERNAL_KEY_CONVERTER_SCHEMAS_ENABLE=false \
  -e CONNECT_INTERNAL_VALUE_CONVERTER=org.apache.kafka.connect.json.JsonConverter \
  -e CONNECT_INTERNAL_VALUE_CONVERTER_SCHEMAS_ENABLE=false \
  \
  -e CONNECT_REST_ADVERTISED_HOST_NAME="kafka-connect" \
  -e CONNECT_REST_PORT=8083 \
  -e CONNECT_PLUGIN_PATH="/kafka/connect,/usr/share/java" \
  -e KAFKA_HEAP_OPTS="${HEAP_OPTS}" \
  \
  "${IMAGE}"

echo ">> waiting for Kafka Connect REST to be up (http://localhost:${CONNECT_REST_PORT}/health)"
# 간단 대기(필요시 더 정교한 헬스체크로 교체 가능)
for i in {1..30}; do
  if curl -fsS "http://localhost:${CONNECT_REST_PORT}/health" >/dev/null 2>&1; then
    echo ">> Kafka Connect is up!"
    break
  fi
  sleep 2
done

echo ">> done."
echo "   - REST API: http://localhost:${CONNECT_REST_PORT}"
echo "   - Connect logs: docker logs -f ${CONNECT_CONTAINER_NAME}"

