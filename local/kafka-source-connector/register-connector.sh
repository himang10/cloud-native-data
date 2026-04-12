#!/bin/bash

# Kafka Connect 설정
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"
CONNECTOR_FILE="${1}"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [ -z "${CONNECTOR_FILE}" ]; then
    echo -e "${RED}오류: 커넥터 파일을 지정해주세요.${NC}"
    echo "사용법: $0 <connector-config.json>"
    echo ""
    echo "예시:"
    echo "  $0 mariadb-source-connector.json"
    echo ""
    echo "사용 가능한 커넥터 파일:"
    ls -1 *.json 2>/dev/null || echo "  (없음)"
    exit 1
fi

if [ ! -f "${CONNECTOR_FILE}" ]; then
    echo -e "${RED}오류: 파일을 찾을 수 없습니다: ${CONNECTOR_FILE}${NC}"
    exit 1
fi

# 커넥터 이름 추출
CONNECTOR_NAME=$(jq -r '.name' "${CONNECTOR_FILE}")

if [ -z "${CONNECTOR_NAME}" ] || [ "${CONNECTOR_NAME}" = "null" ]; then
    echo -e "${RED}오류: 커넥터 파일에서 'name' 필드를 찾을 수 없습니다.${NC}"
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
    echo -e "${RED}오류: Kafka Connect에 연결할 수 없습니다.${NC}"
    echo "  URL: ${KAFKA_CONNECT_URL}"
    echo "  Kafka Connect가 실행 중인지 확인하세요."
    exit 1
fi
echo -e "${GREEN}✓ Kafka Connect 연결 성공${NC}"
echo ""

# 기존 커넥터 확인
echo "기존 커넥터 확인 중..."
EXISTING_CONNECTOR=$(curl -sf "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}" 2>/dev/null)

if [ $? -eq 0 ]; then
    echo -e "${YELLOW}⚠ 커넥터 '${CONNECTOR_NAME}'이 이미 존재합니다.${NC}"
    echo ""
    read -p "기존 커넥터를 삭제하고 다시 생성하시겠습니까? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "기존 커넥터 삭제 중..."
        DELETE_RESPONSE=$(curl -sf -X DELETE "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}")
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 기존 커넥터 삭제 완료${NC}"
            sleep 2
        else
            echo -e "${RED}✗ 커넥터 삭제 실패${NC}"
            exit 1
        fi
    else
        echo "등록을 취소합니다."
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
    echo -e "${GREEN}✓ 커넥터 등록 성공!${NC}"
    echo ""
    echo "===================================="
    echo "등록된 커넥터 정보"
    echo "===================================="
    echo "${RESPONSE}" | jq '.'
    echo ""
    
    # 커넥터 상태 확인
    sleep 2
    echo "커넥터 상태 확인 중..."
    STATUS=$(curl -sf "${KAFKA_CONNECT_URL}/connectors/${CONNECTOR_NAME}/status")
    echo "${STATUS}" | jq '.'
    echo ""
    
    # 상태 요약
    CONNECTOR_STATE=$(echo "${STATUS}" | jq -r '.connector.state')
    TASK_STATE=$(echo "${STATUS}" | jq -r '.tasks[0].state // "N/A"')
    
    echo "===================================="
    echo "상태 요약"
    echo "===================================="
    echo "커넥터 상태: ${CONNECTOR_STATE}"
    echo "태스크 상태: ${TASK_STATE}"
    echo ""
    
    if [ "${CONNECTOR_STATE}" = "RUNNING" ] && [ "${TASK_STATE}" = "RUNNING" ]; then
        echo -e "${GREEN}✓ 커넥터가 정상적으로 실행 중입니다!${NC}"
    else
        echo -e "${YELLOW}⚠ 커넥터가 실행 중이 아닙니다. 로그를 확인하세요.${NC}"
    fi
    echo ""
    
    echo "다음 명령어로 추가 정보를 확인할 수 있습니다:"
    echo "  커넥터 상태: ./check-connector.sh ${CONNECTOR_NAME}"
    echo "  커넥터 삭제: ./delete-connector.sh ${CONNECTOR_NAME}"
    echo "  모든 커넥터: ./list-connectors.sh"
else
    echo -e "${RED}✗ 커넥터 등록 실패${NC}"
    echo ""
    echo "응답:"
    echo "${RESPONSE}"
    exit 1
fi
