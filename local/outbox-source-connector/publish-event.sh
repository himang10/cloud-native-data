#!/bin/bash

echo "===================================="
echo "Outbox 이벤트 발행 테스트"
echo "===================================="
echo ""

# 테스트할 이벤트 타입 선택
echo "발행할 이벤트 타입을 선택하세요:"
echo "1. UserCreated"
echo "2. OrderCreated"
echo "3. ProductCreated"
echo "4. UserUpdated"
echo "5. OrderStatusChanged"
echo ""
read -p "선택 (1-5): " choice

case $choice in
    1)
        EVENT_TYPE="UserCreated"
        AGGREGATE_TYPE="user"
        AGGREGATE_ID="test-user-$(date +%s)"
        PAYLOAD=$(cat <<EOF
{
    "userId": "${AGGREGATE_ID}",
    "username": "testuser_$(date +%s)",
    "email": "test@example.com",
    "fullName": "Test User",
    "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
        ;;
    2)
        EVENT_TYPE="OrderCreated"
        AGGREGATE_TYPE="order"
        AGGREGATE_ID="test-order-$(date +%s)"
        PAYLOAD=$(cat <<EOF
{
    "orderId": "${AGGREGATE_ID}",
    "userId": "user-123",
    "productId": "product-456",
    "quantity": 2,
    "totalPrice": 199.99,
    "status": "pending",
    "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
        ;;
    3)
        EVENT_TYPE="ProductCreated"
        AGGREGATE_TYPE="product"
        AGGREGATE_ID="test-product-$(date +%s)"
        PAYLOAD=$(cat <<EOF
{
    "productId": "${AGGREGATE_ID}",
    "name": "Test Product",
    "description": "This is a test product",
    "price": 99.99,
    "stockQuantity": 100,
    "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
        ;;
    4)
        EVENT_TYPE="UserUpdated"
        AGGREGATE_TYPE="user"
        AGGREGATE_ID="test-user-$(date +%s)"
        PAYLOAD=$(cat <<EOF
{
    "userId": "${AGGREGATE_ID}",
    "username": "updateduser_$(date +%s)",
    "email": "updated@example.com",
    "fullName": "Updated User",
    "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
        ;;
    5)
        EVENT_TYPE="OrderStatusChanged"
        AGGREGATE_TYPE="order"
        AGGREGATE_ID="test-order-$(date +%s)"
        PAYLOAD=$(cat <<EOF
{
    "orderId": "${AGGREGATE_ID}",
    "oldStatus": "pending",
    "newStatus": "shipped",
    "changedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
        ;;
    *)
        echo "잘못된 선택입니다."
        exit 1
        ;;
esac

EVENT_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$(shuf -i 1000-9999 -n 1)")

echo ""
echo "이벤트 정보:"
echo "  Event ID: ${EVENT_ID}"
echo "  Event Type: ${EVENT_TYPE}"
echo "  Aggregate Type: ${AGGREGATE_TYPE}"
echo "  Aggregate ID: ${AGGREGATE_ID}"
echo ""

# MariaDB에 이벤트 삽입
echo "MariaDB에 이벤트 삽입 중..."

# JSON 문자열을 안전하게 처리
PAYLOAD_ESCAPED=$(echo "${PAYLOAD}" | sed 's/"/\\"/g' | tr -d '\n')

docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud <<EOSQL 2>/dev/null
INSERT INTO outbox_events (event_id, aggregate_type, aggregate_id, event_type, payload)
VALUES (
    '${EVENT_ID}',
    '${AGGREGATE_TYPE}',
    '${AGGREGATE_ID}',
    '${EVENT_TYPE}',
    '${PAYLOAD}'
);
EOSQL

if [ $? -eq 0 ]; then
    echo "✓ 이벤트가 outbox_events 테이블에 저장되었습니다."
    echo ""
    
    # 잠시 대기 (CDC 처리 시간)
    echo "CDC 처리 대기 중 (3초)..."
    sleep 3
    
    # Kafka 토픽 확인
    echo ""
    echo "===================================="
    echo "Kafka 토픽 확인"
    echo "===================================="
    
    TOPIC_NAME="outbox.${AGGREGATE_TYPE}"
    echo "토픽: ${TOPIC_NAME}"
    echo ""
    
    echo "최신 메시지 확인:"
    docker exec kafka kafka-console-consumer.sh \
        --bootstrap-server localhost:9092 \
        --topic "${TOPIC_NAME}" \
        --from-beginning \
        --max-messages 1 \
        --timeout-ms 5000 2>/dev/null | tail -1 | jq '.' 2>/dev/null || echo "메시지를 확인할 수 없습니다."
    
    echo ""
    echo "===================================="
    echo "테스트 완료"
    echo "===================================="
    echo ""
    echo "추가 확인 명령어:"
    echo "  • Outbox 테이블: docker exec mariadb-cdc mysql -uskala -p'Skala25a!23\$' cloud -e 'SELECT * FROM outbox_events ORDER BY occurred_at DESC LIMIT 5;'"
    echo "  • Kafka 토픽: ./list-outbox-topics.sh"
    echo "  • 이벤트 확인: ./view-outbox-events.sh ${TOPIC_NAME}"
else
    echo "❌ 오류: 이벤트 삽입 실패"
    exit 1
fi
