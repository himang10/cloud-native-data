#!/bin/bash

echo "===================================="
echo "CDC 파이프라인 전체 테스트"
echo "===================================="
echo ""

# 1. MariaDB에 데이터 추가
echo "1. MariaDB에 새 사용자 추가..."
docker exec mariadb-cdc mysql -uskala -p'Skala25a!23$' cloud -e "
INSERT INTO users (username, email, full_name) 
VALUES ('test_user_$(date +%s)', 'test@example.com', 'Test User CDC');
" 2>/dev/null

echo "   ✓ 데이터 추가 완료"
echo ""

# 2. 잠시 대기 (CDC 처리 시간)
echo "2. CDC 처리 대기 중 (5초)..."
sleep 5
echo ""

# 3. Kafka 토픽 확인
echo "3. Kafka 토픽의 최신 메시지 확인..."
docker exec kafka kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic mariadb-cdc.cloud.users \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 3000 2>/dev/null | tail -1 | jq -r '
    if .payload then
        "   작업: \(.payload.op), 사용자: \(.payload.after.username), 이메일: \(.payload.after.email)"
    else
        "   메시지를 읽을 수 없습니다."
    end
' 2>/dev/null || echo "   Kafka 메시지 확인 실패"
echo ""

# 4. PostgreSQL 확인
echo "4. PostgreSQL의 cdc_users 테이블 확인..."
docker exec pgvector psql -U postgres -d cloud -c "
SELECT COUNT(*) as total_rows FROM cdc_users;
" 2>/dev/null || echo "   테이블이 아직 생성되지 않았습니다."
echo ""

echo "5. PostgreSQL의 최근 데이터 확인..."
docker exec pgvector psql -U postgres -d cloud -c "
SELECT id, username, email, full_name 
FROM cdc_users 
ORDER BY id DESC 
LIMIT 3;
" 2>/dev/null || echo "   데이터를 조회할 수 없습니다."

echo ""
echo "===================================="
echo "테스트 완료"
echo "===================================="
echo ""
echo "다음 명령어로 추가 확인:"
echo "  • MariaDB 데이터: docker exec mariadb-cdc mysql -uskala -p'Skala25a!23\$' cloud -e 'SELECT * FROM users;'"
echo "  • Kafka 토픽: docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list | grep mariadb-cdc"
echo "  • PostgreSQL 데이터: docker exec pgvector psql -U postgres -d cloud -c 'SELECT * FROM cdc_users;'"
