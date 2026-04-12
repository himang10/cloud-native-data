#!/bin/bash

echo "===================================="
echo "Outbox 토픽 목록"
echo "===================================="
echo ""

# Outbox 관련 토픽 조회
echo "1. Outbox 이벤트 토픽:"
docker exec kafka kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --list | grep "^outbox\." | sort

echo ""
echo "2. 스키마 히스토리 토픽:"
docker exec kafka kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --list | grep "mariadb.dbhistory.outbox" | sort

echo ""
echo "3. 에러 토픽:"
docker exec kafka kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --list | grep "outbox-connector-errors" | sort

echo ""
echo "===================================="
echo "토픽 상세 정보"
echo "===================================="

# 각 outbox 토픽의 파티션 정보
for topic in $(docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | grep "^outbox\."); do
    echo ""
    echo "토픽: ${topic}"
    docker exec kafka kafka-topics.sh \
        --bootstrap-server localhost:9092 \
        --describe \
        --topic "${topic}" 2>/dev/null
done

echo ""
echo "===================================="
echo "사용 가능한 명령어"
echo "===================================="
echo "토픽의 메시지 확인: ./view-outbox-events.sh <topic-name>"
echo "예제:"
echo "  ./view-outbox-events.sh outbox.user"
echo "  ./view-outbox-events.sh outbox.order"
echo "  ./view-outbox-events.sh outbox.product"
