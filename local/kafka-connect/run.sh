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

# 현재 스크립트의 디렉토리 경로 가져오기
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Kafka Connect 설정 파일 생성
cat > "${SCRIPT_DIR}/connect-distributed.properties" << EOF
# Bootstrap servers
bootstrap.servers=${KAFKA_BOOTSTRAP}

# Group ID
group.id=source-connect-cluster

# Topic settings
config.storage.topic=source-connect-configs
config.storage.replication.factor=1
offset.storage.topic=source-connect-offsets
offset.storage.replication.factor=1
status.storage.topic=source-connect-status
status.storage.replication.factor=1

# Converters
key.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=true
value.converter=org.apache.kafka.connect.json.JsonConverter
value.converter.schemas.enable=true
internal.key.converter=org.apache.kafka.connect.json.JsonConverter
internal.key.converter.schemas.enable=false
internal.value.converter=org.apache.kafka.connect.json.JsonConverter
internal.value.converter.schemas.enable=false

# REST API
rest.advertised.host.name=localhost
rest.port=8083

# Plugin path
plugin.path=/opt/kafka/plugins,/opt/kafka/libs
EOF

# 시작 스크립트 생성
cat > "${SCRIPT_DIR}/start-kafka-connect.sh" << 'EOF'
#!/bin/bash
exec /opt/kafka/bin/connect-distributed.sh /usr/local/etc/connect-distributed.properties
EOF
chmod +x "${SCRIPT_DIR}/start-kafka-connect.sh"

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
  -v "${SCRIPT_DIR}/connect-distributed.properties:/usr/local/etc/connect-distributed.properties:ro" \
  -v "${SCRIPT_DIR}/start-kafka-connect.sh:/usr/local/bin/start-kafka-connect.sh:ro" \
  -e KAFKA_HEAP_OPTS="-Xms1g -Xmx1g" \
  --memory="2g" \
  --cpus="1.0" \
  ${IMAGE} \
  /usr/local/bin/start-kafka-connect.sh

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
