#!/bin/bash

TOPIC_NAME="${1}"

if [ -z "${TOPIC_NAME}" ]; then
    echo "사용법: $0 <topic-name>"
    echo ""
    echo "사용 가능한 Outbox 토픽:"
    docker exec kafka kafka-topics.sh \
        --bootstrap-server localhost:9092 \
        --list 2>/dev/null | grep -E "^(outbox\.|cloudevents\.)"
    exit 1
fi

echo "===================================="
echo "Outbox 이벤트 확인"
echo "===================================="
echo "토픽: ${TOPIC_NAME}"
echo ""

# 토픽 존재 확인
if ! docker exec kafka kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --list 2>/dev/null | grep -q "^${TOPIC_NAME}$"; then
    echo "❌ 오류: 토픽 '${TOPIC_NAME}'이(가) 존재하지 않습니다."
    exit 1
fi

echo "최근 5개 이벤트 (JSON 포맷):"
echo "------------------------------------"
echo ""

docker exec kafka kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic "${TOPIC_NAME}" \
    --from-beginning \
    --max-messages 5 \
    --timeout-ms 5000 2>/dev/null | while read -r line; do
    echo "${line}" | jq '.' 2>/dev/null || echo "${line}"
    echo ""
done

echo ""
echo "===================================="
echo "실시간 모니터링"
echo "===================================="
echo "실시간으로 이벤트를 모니터링하려면:"
echo ""
echo "docker exec kafka kafka-console-consumer.sh \\"
echo "  --bootstrap-server localhost:9092 \\"
echo "  --topic ${TOPIC_NAME} \\"
echo "  --from-beginning"
echo ""
echo "헤더 포함 확인:"
echo ""
echo "docker exec kafka kafka-console-consumer.sh \\"
echo "  --bootstrap-server localhost:9092 \\"
echo "  --topic ${TOPIC_NAME} \\"
echo "  --from-beginning \\"
echo "  --property print.headers=true \\"
echo "  --property print.timestamp=true"
