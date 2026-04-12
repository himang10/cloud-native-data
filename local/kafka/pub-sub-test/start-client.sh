#!/bin/bash

# Kafka Client 설정
CLIENT_NAME="kafka-client"
IMAGE="confluentinc/cp-kafka:7.4.0"
NETWORK_NAME="kafka-net"
KAFKA_BOOTSTRAP="kafka:9092"

# 기존 클라이언트 컨테이너 확인 및 중지/삭제
if [ "$(docker ps -aq -f name=${CLIENT_NAME})" ]; then
    echo "기존 Kafka 클라이언트 컨테이너를 중지하고 삭제합니다..."
    docker stop ${CLIENT_NAME}
    docker rm ${CLIENT_NAME}
fi

# 네트워크 확인
if ! docker network inspect ${NETWORK_NAME} &> /dev/null; then
    echo "오류: ${NETWORK_NAME} 네트워크가 없습니다."
    echo "Kafka를 먼저 시작하세요."
    exit 1
fi

echo "Kafka 클라이언트 컨테이너를 시작합니다..."

# Kafka Client 컨테이너 실행
docker run -d \
  --name ${CLIENT_NAME} \
  --network ${NETWORK_NAME} \
  ${IMAGE} \
  /bin/bash -c "echo 'Kafka 클라이언트가 준비되었습니다.' && sleep infinity"

# 컨테이너 시작 대기
sleep 3

# 상태 확인
if docker ps | grep -q ${CLIENT_NAME}; then
    echo ""
    echo "===================================="
    echo "Kafka 클라이언트가 시작되었습니다!"
    echo "===================================="
    echo ""
    echo "사용 가능한 명령어:"
    echo "  ./create-topic.sh   - 토픽 생성"
    echo "  ./list-topics.sh    - 토픽 목록 확인"
    echo "  ./producer.sh       - 메시지 전송"
    echo "  ./consumer.sh       - 메시지 수신"
    echo "  ./test-all.sh       - 전체 테스트 실행"
    echo ""
    echo "클라이언트 컨테이너 접속:"
    echo "  docker exec -it ${CLIENT_NAME} bash"
    echo ""
    echo "클라이언트 중지:"
    echo "  docker stop ${CLIENT_NAME}"
    echo ""
else
    echo ""
    echo "오류: Kafka 클라이언트 시작에 실패했습니다."
    echo "로그 확인: docker logs ${CLIENT_NAME}"
    exit 1
fi
