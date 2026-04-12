#!/bin/bash

# Kafka Connect 설정
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"
CONNECTOR_FILE="${1}"

if [ -z "${CONNECTOR_FILE}" ]; then
    echo "사용법: $0 <connector-config.json>"
    echo ""
    echo "예제:"
    echo "  $0 postgresql-sink-connector.json"
    exit 1
fi

if [ ! -f "${CONNECTOR_FILE}" ]; then
    echo "❌ 오류: 파일 '${CONNECTOR_FILE}'을(를) 찾을 수 없습니다."
    exit 1
fi

# 커넥터 이름 추출
CONNECTOR_NAME=$(jq -r '.name' "${CONNECTOR_FILE}")

if [ -z "${CONNECTOR_NAME}" ] || [ "${CONNECTOR_NAME}" = "null" ]; then
    echo "❌ 오류: 커넥터 이름을 찾을 수 없습니다."
    exit 1
fi

echo "===================================="
echo "커넥터 등록 시작"
echo "===================================="
echo "커넥터 이름: ${CONNECTOR_NAME}"
echo "파일: ${CONNECTOR_FILE}"
echo "Kafka Connect URL: ${KAFKA_CONNECT_URL}"
echo ""

# Kafka Connect 상태 확인
echo "Kafka Connect 상태 확인 중..."
if ! curl -sf "${KAFKA_CONNECT_URL}/" > /dev/null; then
    echo "❌ 오류: Kafka Connect에 연결할 수 없습니다."
    echo "   URL: ${KAFKA_CONNECT_URL}"
    exit 1
fi
echo "✓ Kafka Connect 연결 성공"
echo ""

# 기존 커넥터 확인
echo "기존 커넥터 확인 중..."
if curl -sf "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}" > /dev/null 2>&1; then
    echo "⚠ 경고: 커넥터 '${CONNECTOR_NAME}'이(가) 이미 존재합니다."
    read -p "기존 커넥터를 삭제하고 다시 등록하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "기존 커넥터 삭제 중..."
        curl -sf -X DELETE "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}" > /dev/null
        sleep 2
        echo "✓ 기존 커넥터 삭제 완료"
    else
        echo "취소되었습니다."
        exit 0
    fi
fi
echo ""

# 커넥터 등록
echo "커넥터 등록 중..."
RESPONSE=$(curl -sf -X POST \
    -H "Content-Type: application/json" \
    --data @"${CONNECTOR_FILE}" \
    "${KAFKA_CONNECT_URL}/connectors")

if [ $? -eq 0 ]; then
    echo "✓ 커넥터 등록 성공!"
    echo ""
    echo "===================================="
    echo "등록된 커넥터 정보"
    echo "===================================="
    echo "${RESPONSE}" | jq '.'
    
    # 커넥터 상태 확인
    echo ""
    echo "커넥터 상태 확인 중..."
    sleep 2
    STATUS=$(curl -sf "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}/status")
    echo "${STATUS}" | jq '.'
    
    # 상태 요약
    echo ""
    echo "===================================="
    echo "상태 요약"
    echo "===================================="
    CONNECTOR_STATE=$(echo "${STATUS}" | jq -r '.connector.state')
    TASK_STATE=$(echo "${STATUS}" | jq -r '.tasks[0].state // "N/A"')
    
    echo "커넥터 상태: ${CONNECTOR_STATE}"
    echo "태스크 상태: ${TASK_STATE}"
    echo ""
    
    if [ "${CONNECTOR_STATE}" = "RUNNING" ] && [ "${TASK_STATE}" = "RUNNING" ]; then
        echo "✓ 커넥터가 정상적으로 실행 중입니다!"
    else
        echo "⚠ 커넥터가 실행 중이 아닙니다. 로그를 확인하세요."
        echo ""
        echo "로그 확인: docker logs kafka-connect-debezium -f"
    fi
    
    echo ""
    echo "다음 명령어로 추가 정보를 확인할 수 있습니다:"
    echo "  커넥터 상태: curl http://localhost:8083/connectors/${CONNECTOR_NAME}/status | jq"
    echo "  커넥터 삭제: curl -X DELETE http://localhost:8083/connectors/${CONNECTOR_NAME}"
    echo "  모든 커넥터: curl http://localhost:8083/connectors | jq"
else
    echo "❌ 오류: 커넥터 등록 실패"
    exit 1
fi
