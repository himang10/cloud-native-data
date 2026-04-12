#!/bin/bash

# Kafka Connect 설정
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"

echo "===================================="
echo "모든 커넥터 조회"
echo "===================================="
echo ""

# 커넥터 목록 조회
CONNECTORS=$(curl -sf "${KAFKA_CONNECT_URL}/connectors")

if [ $? -ne 0 ]; then
    echo "❌ 오류: Kafka Connect에 연결할 수 없습니다."
    exit 1
fi

CONNECTOR_COUNT=$(echo "${CONNECTORS}" | jq '. | length')

echo "등록된 커넥터 수: ${CONNECTOR_COUNT}"
echo ""

if [ "${CONNECTOR_COUNT}" -eq 0 ]; then
    echo "등록된 커넥터가 없습니다."
    exit 0
fi

# 각 커넥터의 상세 정보 출력
echo "${CONNECTORS}" | jq -r '.[]' | while read -r connector; do
    echo "===================================="
    echo "커넥터: ${connector}"
    echo "===================================="
    
    # 상태 정보
    STATUS=$(curl -sf "${KAFKA_CONNECT_URL}/connectors/${connector}/status")
    CONNECTOR_STATE=$(echo "${STATUS}" | jq -r '.connector.state')
    CONNECTOR_TYPE=$(echo "${STATUS}" | jq -r '.type')
    
    echo "타입: ${CONNECTOR_TYPE}"
    echo "상태: ${CONNECTOR_STATE}"
    
    # 태스크 정보
    TASK_COUNT=$(echo "${STATUS}" | jq '.tasks | length')
    echo "태스크 수: ${TASK_COUNT}"
    
    if [ "${TASK_COUNT}" -gt 0 ]; then
        echo ""
        echo "태스크 상태:"
        echo "${STATUS}" | jq -r '.tasks[] | "  Task \(.id): \(.state)"'
    fi
    
    # 설정 정보 (주요 항목만)
    echo ""
    echo "주요 설정:"
    CONFIG=$(curl -sf "${KAFKA_CONNECT_URL}/connectors/${connector}/config")
    echo "${CONFIG}" | jq -r '{
        class: ."connector.class",
        tasks: ."tasks.max",
        database: ."database.hostname",
        table: ."table.include.list",
        topic_prefix: ."topic.prefix"
    }'
    
    echo ""
done
