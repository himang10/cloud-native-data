#!/bin/bash

# cloud.users 테이블 생성 스크립트
# 사용법: ./create-users-table.sh

NAMESPACE="kafka"
POD="mariadb-1"
CONTAINER="mariadb"
DB_USER="skala"
DB_PASSWORD=$(kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- cat /opt/bitnami/mariadb/secrets/mariadb-password 2>/dev/null || echo 'Skala25a!23$')
DB_HOST="mariadb-1.kafka.svc.cluster.local"
DATABASE="cloud"

MARIADB_CMD="/opt/bitnami/mariadb/bin/mariadb"

echo "=========================================="
echo " cloud.users 테이블 생성"
echo "=========================================="
echo ""

# 테이블 존재 여부 확인
EXISTING=$(kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
  $MARIADB_CMD -u $DB_USER -p"${DB_PASSWORD}" -h $DB_HOST $DATABASE -N -e \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='cloud' AND table_name='users';" 2>/dev/null)

if [ "$EXISTING" = "1" ]; then
  echo " users 테이블이 이미 존재합니다."
  echo ""
  echo " 현재 스키마:"
  kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    $MARIADB_CMD -u $DB_USER -p"${DB_PASSWORD}" -h $DB_HOST $DATABASE -e "DESCRIBE users;" 2>/dev/null
  echo ""
  read -p "테이블을 재생성(DROP & CREATE)하시겠습니까? (y/N): " RECREATE
  if [[ "$RECREATE" != "y" && "$RECREATE" != "Y" ]]; then
    echo " 취소됨."
    exit 0
  fi
  kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    $MARIADB_CMD -u $DB_USER -p"${DB_PASSWORD}" -h $DB_HOST $DATABASE -e "DROP TABLE users;" 2>/dev/null
  echo " 기존 테이블 삭제 완료"
fi

# 테이블 생성 (03.outbox/sql/01-create-outbox-table.sql 스키마와 동일)
kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
  $MARIADB_CMD -u $DB_USER -p"${DB_PASSWORD}" -h $DB_HOST $DATABASE -e "
CREATE TABLE IF NOT EXISTS users (
  id         BIGINT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  email      VARCHAR(100) UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
" 2>/dev/null

if [ $? -eq 0 ]; then
  echo " users 테이블 생성 완료"
  echo ""
  echo " 생성된 스키마:"
  kubectl exec -n $NAMESPACE $POD -c $CONTAINER -- \
    $MARIADB_CMD -u $DB_USER -p"${DB_PASSWORD}" -h $DB_HOST $DATABASE -e "DESCRIBE users;" 2>/dev/null
else
  echo " 테이블 생성 실패"
  exit 1
fi

echo ""
echo "=========================================="
echo " 완료"
echo "=========================================="
echo ""
echo " 다음 단계:"
echo "  - 테스트 데이터 삽입: ./insert-test-data.sh insert 1"
echo "  - CDC 메시지 확인:    Topic 'mariadb-cdc.cloud.users' (Conduktor)"
echo ""
