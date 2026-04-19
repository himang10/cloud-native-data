#!/bin/bash
################################################################################
# MariaDB outbox_events 테이블 생성 스크립트 (Debezium Outbox Pattern 호환)
# - Bitnami MariaDB Pod 내부에서 직접 실행
# - Debezium 3.2.3 EventRouter 완전 호환 구조
# - occurred_at을 TIMESTAMP(3) 타입으로 설정 (Debezium 호환)
################################################################################

set -euo pipefail

# ===== 환경 변수 =====
MARIADB_NAMESPACE="mariadb"
MARIADB_POD="mariadb-1"
MARIADB_CONTAINER="mariadb"

MARIADB_USER="skala"
MARIADB_PASSWORD="Skala25a!23$"
MARIADB_DATABASE="cloud"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MariaDB Outbox 테이블 생성 시작 (TIMESTAMP 타입)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Namespace : $MARIADB_NAMESPACE"
echo "Pod        : $MARIADB_POD"
echo "DB         : $MARIADB_DATABASE"
echo "occurred_at: TIMESTAMP(3) (Debezium 호환)"
echo ""

# ===== Pod 존재 확인 =====
if ! kubectl get pod -n "$MARIADB_NAMESPACE" "$MARIADB_POD" &>/dev/null; then
  echo "MariaDB Pod를 찾을 수 없습니다: $MARIADB_POD"
  exit 1
fi
echo "MariaDB Pod 확인 완료"

# ===== 기존 테이블 백업 및 삭제 확인 =====
echo "기존 outbox_events 테이블 확인 중..."
EXISTING_TABLE=$(kubectl exec -n "$MARIADB_NAMESPACE" "$MARIADB_POD" -c "$MARIADB_CONTAINER" -- \
  /opt/bitnami/mariadb/bin/mariadb \
  -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" \
  -se "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'cloud' AND table_name = 'outbox_events';" 2>/dev/null || echo "0")

if [ "$EXISTING_TABLE" -gt 0 ]; then
  echo " 기존 outbox_events 테이블이 존재합니다."
  echo "백업 생성 후 재생성을 진행합니다..."
  
  # 백업 테이블 생성
  kubectl exec -n "$MARIADB_NAMESPACE" "$MARIADB_POD" -c "$MARIADB_CONTAINER" -- \
    /opt/bitnami/mariadb/bin/mariadb \
    -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" \
    -e "DROP TABLE IF EXISTS outbox_events_backup_$(date +%Y%m%d_%H%M%S);
        CREATE TABLE outbox_events_backup_$(date +%Y%m%d_%H%M%S) AS SELECT * FROM outbox_events;
        DROP TABLE outbox_events;"
  
  echo "기존 테이블 백업 및 삭제 완료"
fi

# ===== 테이블 생성 SQL =====
CREATE_SQL="
-- =====================================================================
--  outbox_events 테이블 (Debezium Outbox Pattern 호환)
--  occurred_at: TIMESTAMP(3) (Debezium EventRouter 호환)
-- =====================================================================

CREATE TABLE IF NOT EXISTS outbox_events (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id        CHAR(36) NOT NULL COMMENT 'UUID 형태의 이벤트 고유 식별자',
    aggregate_id    BIGINT NOT NULL COMMENT '집합체(Aggregate) 식별자',
    aggregate_type  VARCHAR(255) NOT NULL COMMENT '집합체 타입 (Kafka 토픽 라우팅에 사용)',
    event_type      VARCHAR(255) NOT NULL COMMENT '이벤트 타입 (CREATE, UPDATE, DELETE 등)',
    payload         JSON NOT NULL COMMENT '이벤트 페이로드 (JSON 형태)',
    occurred_at     TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3) COMMENT '이벤트 발생 시간 (밀리초 정밀도)',
    processed       TINYINT(1) NOT NULL DEFAULT 0 COMMENT '처리 여부 (0: 미처리, 1: 처리완료)',
    
    CONSTRAINT uq_outbox_event UNIQUE (event_id)
) ENGINE=InnoDB 
  DEFAULT CHARSET=utf8mb4 
  COLLATE=utf8mb4_unicode_ci 
  COMMENT='Debezium Outbox Pattern용 이벤트 테이블 (TIMESTAMP 타입)';

-- =====================================================================
--  인덱스 생성
-- =====================================================================
CREATE INDEX IF NOT EXISTS idx_outbox_aggregate 
    ON outbox_events (aggregate_type, aggregate_id)
    COMMENT '집합체별 이벤트 조회용 인덱스';

CREATE INDEX IF NOT EXISTS idx_outbox_event_type 
    ON outbox_events (event_type)
    COMMENT '이벤트 타입별 조회용 인덱스';

CREATE INDEX IF NOT EXISTS idx_outbox_occurred_at 
    ON outbox_events (occurred_at)
    COMMENT '시간순 정렬용 인덱스';

CREATE INDEX IF NOT EXISTS idx_outbox_processed 
    ON outbox_events (processed, occurred_at)
    COMMENT '미처리 이벤트 조회용 복합 인덱스';
"

# ===== MariaDB 실행 =====
echo " 테이블 생성 중..."
kubectl exec -n "$MARIADB_NAMESPACE" "$MARIADB_POD" -c "$MARIADB_CONTAINER" -- \
  /opt/bitnami/mariadb/bin/mariadb \
  -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "$CREATE_SQL"

if [ $? -eq 0 ]; then
  echo "outbox_events 테이블 생성 완료!"
else
  echo "테이블 생성 실패!"
  exit 1
fi

# ===== 생성 확인 =====
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "테이블 구조 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

kubectl exec -n "$MARIADB_NAMESPACE" "$MARIADB_POD" -c "$MARIADB_CONTAINER" -- \
  /opt/bitnami/mariadb/bin/mariadb \
  -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" \
  -e "SHOW CREATE TABLE outbox_events\G"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "컬럼 정보 상세 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

kubectl exec -n "$MARIADB_NAMESPACE" "$MARIADB_POD" -c "$MARIADB_CONTAINER" -- \
  /opt/bitnami/mariadb/bin/mariadb \
  -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" \
  -e "DESCRIBE outbox_events;"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "테스트 데이터 삽입 (현재 TIMESTAMP)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CURRENT_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TEST_EVENT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

kubectl exec -n "$MARIADB_NAMESPACE" "$MARIADB_POD" -c "$MARIADB_CONTAINER" -- \
  /opt/bitnami/mariadb/bin/mariadb \
  -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "
INSERT INTO outbox_events (
    event_id,
    aggregate_id,
    aggregate_type,
    event_type,
    payload,
    occurred_at,
    processed
) VALUES (
    '$TEST_EVENT_ID',
    12345,
    'test',
    'TABLE_CREATED',
    JSON_OBJECT(
        'message', '테이블 생성 테스트',
        'timestamp', '$CURRENT_TIMESTAMP',
        'table_type', 'TIMESTAMP(3)'
    ),
    '$CURRENT_TIMESTAMP',
    0
);

-- 삽입된 테스트 데이터 확인
SELECT 
    event_id,
    aggregate_type,
    event_type,
    occurred_at,
    payload
FROM outbox_events 
WHERE event_id = '$TEST_EVENT_ID'\G
"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MariaDB outbox_events 테이블 생성 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "주요 변경사항:"
echo "   - occurred_at: BIGINT → TIMESTAMP(3) (Debezium 호환)"
echo "   - 기존 테이블 백업 후 재생성"
echo "   - 테스트 데이터 자동 삽입"
echo ""
echo "다음 단계:"
echo "   1. Kafka Connector 설정 적용"
echo "   2. 이벤트 삽입 테스트 실행"
echo "   3. Kafka 토픽 확인"
echo ""
echo "Test Event ID: $TEST_EVENT_ID"
echo "Current Timestamp: $CURRENT_TIMESTAMP"