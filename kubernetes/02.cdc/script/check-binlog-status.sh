#!/bin/bash

# MariaDB Binlog 상태 확인 스크립트
# 사용법: ./check-binlog-status.sh

set -e

NAMESPACE="kafka"
POD="mariadb-1-0"
CONTAINER="mariadb"
DB_USER="root"
DB_PASSWORD="Skala25a!23\$"

echo "=========================================="
echo " MariaDB Binlog 상태 확인"
echo "=========================================="
echo ""

# 1. Binlog 설정 확인
echo ""
echo "  Binlog 설정"
echo ""
echo ""

kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    mysql -u $DB_USER -p"$DB_PASSWORD" -e "
    SHOW VARIABLES LIKE 'log_bin';
    SHOW VARIABLES LIKE 'binlog_format';
    SHOW VARIABLES LIKE 'binlog_row_image';
    SHOW VARIABLES LIKE 'server_id';
    SHOW VARIABLES LIKE 'expire_logs_days';
    SHOW VARIABLES LIKE 'max_binlog_size';
" 2>/dev/null | grep -v "mysql: Deprecated" || true

echo ""

# 설정 검증
LOG_BIN=$(kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    mysql -u $DB_USER -p"$DB_PASSWORD" -N -e "SHOW VARIABLES LIKE 'log_bin';" 2>/dev/null | awk '{print $2}')

BINLOG_FORMAT=$(kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    mysql -u $DB_USER -p"$DB_PASSWORD" -N -e "SHOW VARIABLES LIKE 'binlog_format';" 2>/dev/null | awk '{print $2}')

echo ""
echo " 설정 검증"
echo ""
echo ""

if [ "$LOG_BIN" = "ON" ]; then
    echo " Binlog 활성화: ON"
else
    echo " Binlog 비활성화: OFF"
fi

if [ "$BINLOG_FORMAT" = "ROW" ]; then
    echo " Binlog 형식: ROW (CDC 지원)"
else
    echo " Binlog 형식: $BINLOG_FORMAT (CDC 미지원)"
fi

echo ""

# 2. Binlog 파일 목록
echo ""
echo " Binlog 파일 목록"
echo ""
echo ""

kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    mysql -u $DB_USER -p"$DB_PASSWORD" -e "SHOW BINARY LOGS;" 2>/dev/null | grep -v "mysql: Deprecated" || true

echo ""

# 3. Master 상태
echo ""
echo " Master 상태 (현재 Binlog 위치)"
echo ""
echo ""

kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    mysql -u $DB_USER -p"$DB_PASSWORD" -e "SHOW MASTER STATUS;" 2>/dev/null | grep -v "mysql: Deprecated" || true

echo ""

# 4. 사용자 권한 확인
echo ""
echo " CDC 사용자 권한 (skala)"
echo ""
echo ""

kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    mysql -u $DB_USER -p"$DB_PASSWORD" -e "SHOW GRANTS FOR 'skala'@'%';" 2>/dev/null | grep -v "mysql: Deprecated" || true

echo ""

# 권한 검증
GRANTS=$(kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    mysql -u $DB_USER -p"$DB_PASSWORD" -N -e "SHOW GRANTS FOR 'skala'@'%';" 2>/dev/null | head -1)

echo ""
echo " 권한 검증"
echo ""
echo ""

if echo "$GRANTS" | grep -q "RELOAD"; then
    echo " RELOAD 권한: 있음"
else
    echo " RELOAD 권한: 없음"
fi

if echo "$GRANTS" | grep -q "REPLICATION SLAVE"; then
    echo " REPLICATION SLAVE 권한: 있음"
else
    echo " REPLICATION SLAVE 권한: 없음"
fi

if echo "$GRANTS" | grep -q "REPLICATION CLIENT"; then
    echo " REPLICATION CLIENT 권한: 있음"
else
    echo " REPLICATION CLIENT 권한: 없음"
fi

echo ""

# 5. 데이터베이스 및 테이블 정보
echo ""
echo "  데이터베이스 정보 (cloud)"
echo ""
echo ""

kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    mysql -u $DB_USER -p"$DB_PASSWORD" cloud -e "
    SELECT 
        table_name as '테이블명',
        table_rows as '레코드 수',
        ROUND(data_length / 1024 / 1024, 2) as '크기(MB)'
    FROM information_schema.tables 
    WHERE table_schema = 'cloud' 
    ORDER BY table_name;
" 2>/dev/null | grep -v "mysql: Deprecated" || true

echo ""

# 최종 상태 요약
echo "=========================================="
echo " Binlog CDC 준비 상태 요약"
echo "=========================================="
echo ""

READY=true

if [ "$LOG_BIN" != "ON" ]; then
    echo " Binlog가 비활성화되어 있습니다"
    READY=false
fi

if [ "$BINLOG_FORMAT" != "ROW" ]; then
    echo " Binlog 형식이 ROW가 아닙니다"
    READY=false
fi

if ! echo "$GRANTS" | grep -q "RELOAD"; then
    echo " RELOAD 권한이 없습니다"
    READY=false
fi

if ! echo "$GRANTS" | grep -q "REPLICATION SLAVE"; then
    echo " REPLICATION SLAVE 권한이 없습니다"
    READY=false
fi

if [ "$READY" = true ]; then
    echo " CDC를 위한 모든 설정이 완료되었습니다!"
    echo ""
    echo " 다음 단계:"
    echo "  1. Connector 배포: kubectl apply -f mariadb-source-connector.yaml"
    echo "  2. 상태 확인: ./check-connector-status.sh"
    echo "  3. 테스트 데이터 삽입: ./insert-test-data.sh insert 3"
    echo "  4. CDC 메시지 확인: ./view-cdc-messages.sh"
else
    echo ""
    echo "  일부 설정이 누락되었습니다."
    echo ""
    echo " 설정 가이드:"
    echo "  MARIADB_BINLOG_GUIDE.md 파일을 참조하세요"
fi

echo ""
echo "=========================================="

