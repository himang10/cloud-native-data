#!/bin/bash
################################################################################
# MariaDB outbox_events 테이블에 테스트 이벤트 삽입 스크립트 (TIMESTAMP 타입)
################################################################################

set -e

MARIADB_NAMESPACE="mariadb"
MARIADB_POD="mariadb-1"
MARIADB_CONTAINER="mariadb"
MARIADB_USER="skala"
MARIADB_PASSWORD="Skala25a!23$"
MARIADB_DATABASE="cloud"

EVENT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
TIMESTAMP_STR=$(date '+%Y-%m-%d %H:%M:%S')

# TIMESTAMP_MILLIS=$(date +%s%3N)  # Unix timestamp in milliseconds

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MariaDB Outbox Event 삽입 테스트 (TIMESTAMP 타입)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Event ID: $EVENT_ID"
echo "Aggregate Type: user (→ 토픽: outbox.user)"
echo "Timestamp: $TIMESTAMP_STR"
echo ""


# MariaDB Pod 확인
echo "MariaDB Pod 확인 중..."
if ! kubectl get pod -n "$MARIADB_NAMESPACE" "$MARIADB_POD" &>/dev/null; then
    echo "MariaDB Pod를 찾을 수 없습니다: $MARIADB_POD"
    exit 1
fi
echo "MariaDB Pod 발견"

# Outbox Event 삽입
echo ""
echo "Outbox Event 삽입 중..."

kubectl exec -n "$MARIADB_NAMESPACE" "$MARIADB_POD" -c "$MARIADB_CONTAINER" -- \
    /opt/bitnami/mariadb/bin/mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "
INSERT INTO outbox_events (
    event_id,
    aggregate_id,
    aggregate_type,
    event_type,
    payload,
    occurred_at,
    processed
) VALUES (
    '$EVENT_ID',
    $(date +%s),
    'user',
    'CREATED',
    JSON_OBJECT(
        'id', $(date +%s),
        'name', '테스트사용자-$(date +%H%M%S)',
        'email', 'test-$(date +%H%M%S)@example.com',
        'timestamp', '$TIMESTAMP_STR'
    ),
    '$TIMESTAMP_STR',  -- TIMESTAMP 타입으로 직접 삽입
    0
);
"

if [ $? -eq 0 ]; then
    echo "Outbox Event 삽입 성공!"
else
    echo "Outbox Event 삽입 실패!"
    exit 1
fi

# 삽입된 이벤트 확인
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "삽입된 이벤트 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

kubectl exec -n "$MARIADB_NAMESPACE" "$MARIADB_POD" -c "$MARIADB_CONTAINER" -- \
    /opt/bitnami/mariadb/bin/mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "
SELECT 
    id,
    event_id,
    aggregate_id,
    aggregate_type,
    event_type,
    payload,
    occurred_at,
    processed
FROM outbox_events 
WHERE event_id = '$EVENT_ID'\G
"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "테스트 이벤트 삽입 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Event ID: $EVENT_ID"
echo "Timestamp: $TIMESTAMP_STR"
echo "예상 Kafka 토픽: outbox.user"
echo ""
echo "다음 단계: Debezium이 이벤트를 처리할 때까지 5-10초 대기 후"
echo "           ./test-02-check-kafka-topic.sh 실행"
