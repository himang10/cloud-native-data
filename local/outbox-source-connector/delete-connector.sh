#!/bin/bash

# Kafka Connect 설정
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"
CONNECTOR_NAME="${1}"

if [ -z "${CONNECTOR_NAME}" ]; then
    echo "사용법: $0 <connector-name>"
    echo ""
    echo "등록된 커넥터 목록:"
    curl -sf "${KAFKA_CONNECT_URL}/connectors" | jq -r '.[]'
    exit 1
fi

# 커넥터 존재 확인
if ! curl -sf "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}" > /dev/null; then
    echo "❌ 오류: 커넥터 '${CONNECTOR_NAME}'이(가) 존재하지 않습니다."
    exit 1
fi

echo "===================================="
echo "커넥터 삭제"
echo "===================================="
echo "커넥터: ${CONNECTOR_NAME}"
echo ""

# 커넥터 상태 확인
echo "현재 상태:"
curl -sf "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}/status" | jq '{name: .name, state: .connector.state, tasks: [.tasks[] | {id: .id, state: .state}]}'
echo ""

# 삭제 확인
read -p "정말로 이 커넥터를 삭제하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

# 커넥터 삭제
echo ""
echo "커넥터를 삭제하는 중..."
HTTP_CODE=$(curl -sf -w "%{http_code}" -X DELETE "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}" -o /dev/null)

if [ "${HTTP_CODE}" -eq 204 ] || [ "${HTTP_CODE}" -eq 200 ]; then
    echo "✅ 성공: 커넥터 '${CONNECTOR_NAME}'이(가) 삭제되었습니다."
else
    echo "❌ 오류: 커넥터 삭제 실패 (HTTP ${HTTP_CODE})"
    exit 1
fi

# 삭제 확인
echo ""
echo "남은 커넥터:"
curl -sf "${KAFKA_CONNECT_URL}/connectors" | jq -r '.[]'
