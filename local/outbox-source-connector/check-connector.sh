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

echo "===================================="
echo "커넥터 상세 정보"
echo "===================================="
echo "커넥터: ${CONNECTOR_NAME}"
echo ""

# 커넥터 상태
echo "1. 상태 정보"
echo "------------------------------------"
curl -sf "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}/status" | jq '.'
echo ""

# 커넥터 설정
echo "2. 설정 정보"
echo "------------------------------------"
curl -sf "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}/config" | jq '.'
echo ""

# 커넥터 태스크
echo "3. 태스크 정보"
echo "------------------------------------"
curl -sf "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}/tasks" | jq '.'
echo ""

echo "===================================="
echo "추가 명령어"
echo "===================================="
echo "재시작: curl -X POST ${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}/restart"
echo "일시정지: curl -X PUT ${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}/pause"
echo "재개: curl -X PUT ${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}/resume"
echo "삭제: ./delete-connector.sh ${CONNECTOR_NAME}"
