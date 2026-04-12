#!/bin/bash

CLIENT_NAME="kafka-client"
KAFKA_BOOTSTRAP="kafka:9092"
TOPIC_NAME="test-topic"

echo "===================================="
echo "Kafka Pub/Sub 전체 테스트 시작"
echo "===================================="
echo ""

# 1. 토픽 생성
echo "1. 토픽 생성..."
./create-topic.sh ${TOPIC_NAME} 3 1
if [ $? -ne 0 ]; then
    echo "토픽이 이미 존재하거나 생성에 실패했습니다. 계속 진행합니다..."
fi
echo ""

# 2. 토픽 목록 확인
echo "2. 토픽 목록 확인..."
./list-topics.sh
echo ""

# 3. 메시지 전송 (비대화형)
echo "3. 테스트 메시지 전송..."
TEST_MESSAGES=(
    "Hello Kafka!"
    "Test message 1"
    "Test message 2"
    "Test message 3"
    "Goodbye Kafka!"
)

for msg in "${TEST_MESSAGES[@]}"; do
    echo "${msg}" | docker exec -i ${CLIENT_NAME} kafka-console-producer \
        --topic ${TOPIC_NAME} \
        --bootstrap-server ${KAFKA_BOOTSTRAP}
    echo "  전송: ${msg}"
    sleep 1
done
echo ""

# 4. 메시지 수신 (타임아웃 5초)
echo "4. 메시지 수신 테스트..."
echo "  (5초 동안 메시지를 수신합니다...)"
echo ""

timeout 5s docker exec ${CLIENT_NAME} kafka-console-consumer \
    --topic ${TOPIC_NAME} \
    --from-beginning \
    --bootstrap-server ${KAFKA_BOOTSTRAP} \
    --max-messages 5

echo ""
echo ""
echo "===================================="
echo "테스트 완료!"
echo "===================================="
echo ""
echo "추가 테스트를 원하시면:"
echo "  Producer: ./producer.sh ${TOPIC_NAME}"
echo "  Consumer: ./consumer.sh ${TOPIC_NAME}"
