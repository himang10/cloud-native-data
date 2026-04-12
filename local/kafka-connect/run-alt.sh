#!/bin/bash

# Kafka Connect 설정
CONTAINER_NAME="kafka-connect-debezium"
IMAGE="amdp-registry.skala-ai.com/library/skala-kafka-connect:debezium-3.2.3-kafka-4.0"
KAFKA_BOOTSTRAP="kafka:9092"
NETWORK_NAME="kafka-net"  # ← Kafka와 동일한 네트워크
REST_PORT="8083"

# 기존 컨테이너 확인 및 중지/삭제
if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
    echo "기존 컨테이너를 중지하고 삭제합니다..."
    docker stop ${CONTAINER_NAME}
    docker rm ${CONTAINER_NAME}
fi

# 네트워크 존재 확인 (없으면 생성)
if ! docker network inspect ${NETWORK_NAME} &> /dev/null; then
    echo "네트워크 ${NETWORK_NAME}이 없습니다. 생성합니다..."
    docker network create ${NETWORK_NAME}
fi

echo "Kafka Connect 컨테이너를 시작합니다..."

# 아키텍처 감지
ARCH=$(uname -m)
PLATFORM_FLAG=""

if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    echo "ARM64 아키텍처가 감지되었습니다..."
    PLATFORM_FLAG="--platform linux/arm64"
    IMAGE="${IMAGE}-arm64"
fi

# Docker 컨테이너 실행
docker run -d \
  $PLATFORM_FLAG \
  --name ${CONTAINER_NAME} \
  --network ${NETWORK_NAME} \
  -p ${REST_PORT}:8083 \
  -e KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP}" \
  -e KAFKA_GROUP_ID="source-connect-cluster" \
  -e KAFKA_CONFIG_STORAGE_TOPIC="source-connect-configs" \
  -e KAFKA_CONFIG_STORAGE_REPLICATION_FACTOR="1" \
  -e KAFKA_OFFSET_STORAGE_TOPIC="source-connect-offsets" \
  -e KAFKA_OFFSET_STORAGE_REPLICATION_FACTOR="1" \
  -e KAFKA_STATUS_STORAGE_TOPIC="source-connect-status" \
  -e KAFKA_STATUS_STORAGE_REPLICATION_FACTOR="1" \
  -e KAFKA_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e KAFKA_KEY_CONVERTER_SCHEMAS_ENABLE="true" \
  -e KAFKA_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e KAFKA_VALUE_CONVERTER_SCHEMAS_ENABLE="true" \
  -e KAFKA_INTERNAL_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e KAFKA_INTERNAL_KEY_CONVERTER_SCHEMAS_ENABLE="false" \
  -e KAFKA_INTERNAL_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e KAFKA_INTERNAL_VALUE_CONVERTER_SCHEMAS_ENABLE="false" \
  -e KAFKA_REST_ADVERTISED_HOST_NAME="localhost" \
  -e KAFKA_REST_PORT="8083" \
  -e KAFKA_PLUGIN_PATH="/opt/kafka/plugins,/opt/kafka/libs" \
  -e KAFKA_HEAP_OPTS="-Xms1g -Xmx1g" \
  --memory="2g" \
  --cpus="1.0" \
  ${IMAGE} \
  /bin/bash -c '
    cat > /tmp/connect-distributed.properties << EOF
bootstrap.servers=${KAFKA_BOOTSTRAP_SERVERS}
group.id=${KAFKA_GROUP_ID}
config.storage.topic=${KAFKA_CONFIG_STORAGE_TOPIC}
config.storage.replication.factor=${KAFKA_CONFIG_STORAGE_REPLICATION_FACTOR}
offset.storage.topic=${KAFKA_OFFSET_STORAGE_TOPIC}
offset.storage.replication.factor=${KAFKA_OFFSET_STORAGE_REPLICATION_FACTOR}
status.storage.topic=${KAFKA_STATUS_STORAGE_TOPIC}
status.storage.replication.factor=${KAFKA_STATUS_STORAGE_REPLICATION_FACTOR}
key.converter=${KAFKA_KEY_CONVERTER}
key.converter.schemas.enable=${KAFKA_KEY_CONVERTER_SCHEMAS_ENABLE}
value.converter=${KAFKA_VALUE_CONVERTER}
value.converter.schemas.enable=${KAFKA_VALUE_CONVERTER_SCHEMAS_ENABLE}
internal.key.converter=${KAFKA_INTERNAL_KEY_CONVERTER}
internal.key.converter.schemas.enable=${KAFKA_INTERNAL_KEY_CONVERTER_SCHEMAS_ENABLE}
internal.value.converter=${KAFKA_INTERNAL_VALUE_CONVERTER}
internal.value.converter.schemas.enable=${KAFKA_INTERNAL_VALUE_CONVERTER_SCHEMAS_ENABLE}
rest.advertised.host.name=${KAFKA_REST_ADVERTISED_HOST_NAME}
rest.port=${KAFKA_REST_PORT}
plugin.path=${KAFKA_PLUGIN_PATH}
EOF
    exec /opt/kafka/bin/connect-distributed.sh /tmp/connect-distributed.properties
  '

# 컨테이너 시작 대기
echo "Kafka Connect가 시작될 때까지 대기 중..."
sleep 15

# 상태 확인
if docker ps | grep -q ${CONTAINER_NAME}; then
    echo ""
    echo "===================================="
    echo "Kafka Connect가 성공적으로 시작되었습니다!"
    echo "===================================="
    echo ""
    echo "접속 정보:"
    echo "  REST API: http://localhost:${REST_PORT}"
    echo "  Kafka Bootstrap: ${KAFKA_BOOTSTRAP}"
    echo "  Group ID: source-connect-cluster"
    echo ""
    echo "상태 확인:"
    echo "  curl http://localhost:${REST_PORT}/ | jq"
    echo ""
    echo "커넥터 목록:"
    echo "  curl http://localhost:${REST_PORT}/connectors | jq"
    echo ""
    echo "플러그인 목록:"
    echo "  curl http://localhost:${REST_PORT}/connector-plugins | jq"
    echo ""
    echo "컨테이너 로그:"
    echo "  docker logs -f ${CONTAINER_NAME}"
    echo ""
    echo "컨테이너 중지:"
    echo "  docker stop ${CONTAINER_NAME}"
    echo ""
else
    echo ""
    echo "오류: Kafka Connect 시작에 실패했습니다."
    echo "로그 확인: docker logs ${CONTAINER_NAME}"
    exit 1
fi
