#!/bin/bash

# MariaDB 테스트 데이터 삽입 스크립트
# 사용법: ./insert-test-data.sh [operation] [count]
# operation: insert|update|delete
# count: 생성할 레코드 수 (기본: 1)

set -e

NAMESPACE="kafka"
POD="mariadb-1-0"
CONTAINER="mariadb"
DB_USER="skala"
# 비밀번호는 Secret 파일에서 읽기 (특수문자 이스케이프 문제 방지)
DB_PASSWORD=$(kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- cat /opt/bitnami/mariadb/secrets/mariadb-password 2>/dev/null || echo 'Skala25a!23$')
DB_HOST="127.0.0.1"
DATABASE="cloud"

OPERATION=${1:-"insert"}
COUNT=${2:-1}

echo "=========================================="
echo " MariaDB 테스트 데이터 작업"
echo "=========================================="
echo ""
echo " 작업: $OPERATION"
echo " 대상 테이블: users"
echo " 레코드 수: $COUNT"
echo ""

case $OPERATION in
    insert)
        echo " INSERT 작업 시작..."
        for i in $(seq 1 $COUNT); do
            TIMESTAMP=$(date +%s)
            USER_NAME="Test User ${TIMESTAMP} #${i}"
            USER_EMAIL="test${TIMESTAMP}_${i}@example.com"

            SQL="INSERT INTO users (name, email) VALUES ('${USER_NAME}', '${USER_EMAIL}');"

            kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
                /opt/bitnami/mariadb/bin/mariadb -u $DB_USER -p"${DB_PASSWORD}" -h $DB_HOST $DATABASE -e "$SQL"

            echo "   생성됨: ${USER_NAME} / ${USER_EMAIL}"
        done

        echo ""
        echo " $COUNT 개의 레코드 INSERT 완료"
        ;;

    update)
        echo " UPDATE 작업 시작..."

        # 최근 레코드 id 조회
        RECENT_IDS=$(kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
            /opt/bitnami/mariadb/bin/mariadb -u $DB_USER -p"${DB_PASSWORD}" -h $DB_HOST $DATABASE -N -e \
            "SELECT id FROM users ORDER BY id DESC LIMIT $COUNT;")

        if [ -z "$RECENT_IDS" ]; then
            echo " 업데이트할 레코드가 없습니다."
            exit 1
        fi

        COUNTER=0
        while IFS= read -r ROW_ID; do
            TIMESTAMP=$(date +%s)
            NEW_NAME="Updated User ${TIMESTAMP} #${ROW_ID}"

            SQL="UPDATE users SET name = '${NEW_NAME}' WHERE id = ${ROW_ID};"

            kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
                /opt/bitnami/mariadb/bin/mariadb -u $DB_USER -p"${DB_PASSWORD}" -h $DB_HOST $DATABASE -e "$SQL"

            echo "   업데이트됨: id=${ROW_ID} -> ${NEW_NAME}"
            COUNTER=$((COUNTER + 1))
        done <<< "$RECENT_IDS"

        echo ""
        echo " $COUNTER 개의 레코드 UPDATE 완료"
        ;;

    delete)
        echo "  DELETE 작업 시작..."

        # 최근 레코드 id 조회
        RECENT_IDS=$(kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
            /opt/bitnami/mariadb/bin/mariadb -u $DB_USER -p"${DB_PASSWORD}" -h $DB_HOST $DATABASE -N -e \
            "SELECT id FROM users ORDER BY id DESC LIMIT $COUNT;")

        if [ -z "$RECENT_IDS" ]; then
            echo " 삭제할 레코드가 없습니다."
            exit 1
        fi

        COUNTER=0
        while IFS= read -r ROW_ID; do
            SQL="DELETE FROM users WHERE id = ${ROW_ID};"

            kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
                /opt/bitnami/mariadb/bin/mariadb -u $DB_USER -p"${DB_PASSWORD}" -h $DB_HOST $DATABASE -e "$SQL"

            echo "   삭제됨: id=${ROW_ID}"
            COUNTER=$((COUNTER + 1))
        done <<< "$RECENT_IDS"

        echo ""
        echo " $COUNTER 개의 레코드 DELETE 완료"
        ;;
        
    *)
        echo " 잘못된 작업: $OPERATION"
        echo ""
        echo "사용 가능한 작업:"
        echo "  - insert: 새 레코드 삽입"
        echo "  - update: 기존 레코드 업데이트"
        echo "  - delete: 기존 레코드 삭제"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo " 현재 users 테이블 레코드 수"
echo "=========================================="

kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    /opt/bitnami/mariadb/bin/mariadb -u $DB_USER -p"${DB_PASSWORD}" -h $DB_HOST $DATABASE -e "SELECT COUNT(*) as total_users FROM users;"

echo ""
echo " 사용 팁:"
echo "  - 5개 삽입: ./insert-test-data.sh insert 5"
echo "  - 3개 업데이트: ./insert-test-data.sh update 3"
echo "  - 2개 삭제: ./insert-test-data.sh delete 2"
echo ""

