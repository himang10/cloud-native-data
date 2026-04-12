#!/bin/bash

# Kafka Connect 설정
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"

echo "===================================="
echo "Kafka Connect 커넥터 목록"
echo "===================================="
echo "Kafka Connect URL: ${KAFKA_CONNECT_URL}"
echo ""

# Kafka Connect 상태 확인
if ! curl -sf "${KAFKA_CONNECT_URL}/" > /dev/null; then
    echo "오류: Kafka Connect에 연결할 수 없습니다."
    exit 1
fi

# 커넥터 목록 조회
CONNECTORS=$(curl -sf "${KAFKA_CONNECT_URL}/connectors")

if [ $? -eq 0 ]; then
    CONNECTOR_COUNT=$(echo "${CONNECTORS}" | jq '. | length')
    
    if [ "${CONNECTOR_COUNT}" -eq 0 ]; then
        echo "등록된 커넥터가 없습니다."
    else
        echo "등록된 커넥터 수: ${CONNECTOR_COUNT}"
        echo ""
        echo "${CONNECTORS}" | jq -r '.[]' | while read -r connector; do
            echo "------------------------------------"
            echo "커넥터: ${connector}"
            
            # 각 커넥터의 상태 조회
            STATUS=$(curl -sf "${KAFKA_CONNECT_URL}/connectors/${connector}/status")
            CONNECTOR_STATE=$(echo "${STATUS}" | jq -r '.connector.state')
            TASK_STATE=$(echo "${STATUS}" | jq -r '.tasks[0].state // "N/A"')
            TASK_ID=$(echo "${STATUS}" | jq -r '.tasks[0].id // "N/A"')
            
            echo "  상태: ${CONNECTOR_STATE}"
            echo "  태스크 ID: ${TASK_ID}"
            echo "  태스크 상태: ${TASK_STATE}"
            
            # 설정 정보
            CONFIG=$(curl -sf "${KAFKA_CONNECT_URL}/connectors/${connector}/config")
            CONNECTOR_CLASS=$(echo "${CONFIG}" | jq -r '."connector.class"')
            TASKS_MAX=$(echo "${CONFIG}" | jq -r '."tasks.max"')
            
            echo "  클래스: ${CONNECTOR_CLASS}"
            echo "  최대 태스크: ${TASKS_MAX}"
        done
        echo "------------------------------------"
    fi
    echo ""
    echo "상세 정보 확인:"
    echo "  ./check-connector.sh <connector-name>"
else
    echo "오류: 커넥터 목록을 가져올 수 없습니다."
    exit 1
fi
