#!/bin/bash

# ============================================================
# Kafka 클러스터 동작 테스트 스크립트
# kafka-client Pod를 통해 Producer/Consumer 동작을 검증합니다.
# ============================================================

set -e

# ---- 설정 ----
NAMESPACE="kafka"
CLIENT_POD="kafka-client"
# 클러스터 내부 접속 (Plain, 인증 없음)
BOOTSTRAP_INTERNAL="my-kafka-cluster-kafka-bootstrap.kafka.svc:9092"
# 클러스터 외부 접속 (LoadBalancer)
BOOTSTRAP_EXTERNAL="my-kafka-cluster-kafka-external-bootstrap:9094"
TOPIC="my-topic"
TEST_MESSAGE="Hello Kafka - $(date '+%Y-%m-%d %H:%M:%S')"
TIMEOUT=15  # Consumer 대기 시간(초)

# ---- 색상 출력 ----
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAILED=$((FAILED+1)); }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

FAILED=0

echo "=============================================="
echo "  Kafka 클러스터 동작 테스트"
echo "  Bootstrap : ${BOOTSTRAP_INTERNAL}"
echo "  Topic     : ${TOPIC}"
echo "  Namespace : ${NAMESPACE}"
echo "=============================================="
echo ""

# ---- 1. kafka-client Pod 상태 확인 ----
info "1. kafka-client Pod 상태 확인..."
POD_STATUS=$(kubectl get pod "${CLIENT_POD}" -n "${NAMESPACE}" \
    --no-headers -o custom-columns=":status.phase" 2>/dev/null || echo "NotFound")

if [[ "${POD_STATUS}" == "Running" ]]; then
    ok "kafka-client Pod 실행 중"
else
    fail "kafka-client Pod 상태: ${POD_STATUS}"
    echo "  → kubectl apply -f kubernetes/kafka/kafka-client.yaml"
    exit 1
fi

# ---- 2. Kafka 브로커 연결 확인 ----
info "2. Kafka 브로커 연결 확인 (${BOOTSTRAP_INTERNAL})..."
BROKER_CHECK=$(kubectl exec "${CLIENT_POD}" -n "${NAMESPACE}" -- \
    kafka-broker-api-versions \
    --bootstrap-server "${BOOTSTRAP_INTERNAL}" 2>&1 | head -1 || echo "FAILED")

if echo "${BROKER_CHECK}" | grep -q "FAILED\|Error\|Exception"; then
    fail "브로커 연결 실패: ${BROKER_CHECK}"
else
    ok "브로커 연결 성공"
fi

# ---- 3. 토픽 목록 확인 ----
info "3. 토픽 목록 조회..."
TOPICS=$(kubectl exec "${CLIENT_POD}" -n "${NAMESPACE}" -- \
    kafka-topics \
    --bootstrap-server "${BOOTSTRAP_INTERNAL}" \
    --list 2>&1)

if echo "${TOPICS}" | grep -q "${TOPIC}"; then
    ok "토픽 [${TOPIC}] 존재 확인"
else
    fail "토픽 [${TOPIC}] 없음. 전체 토픽 목록:"
    echo "${TOPICS}" | sed 's/^/       /'
fi

# ---- 4. 토픽 상세 정보 ----
info "4. 토픽 상세 정보..."
kubectl exec "${CLIENT_POD}" -n "${NAMESPACE}" -- \
    kafka-topics \
    --bootstrap-server "${BOOTSTRAP_INTERNAL}" \
    --describe --topic "${TOPIC}" 2>&1 | sed 's/^/  /'
echo ""

# ---- 5. Producer 테스트 ----
info "5. 메시지 발행 (Producer)..."
info "   메시지: \"${TEST_MESSAGE}\""
echo "${TEST_MESSAGE}" | kubectl exec -i "${CLIENT_POD}" -n "${NAMESPACE}" -- \
    kafka-console-producer \
    --bootstrap-server "${BOOTSTRAP_INTERNAL}" \
    --topic "${TOPIC}" 2>&1

ok "메시지 발행 완료"

# ---- 6. Consumer 테스트 ----
info "6. 메시지 구독 (Consumer, ${TIMEOUT}초 대기)..."
CONSUMED=$(kubectl exec "${CLIENT_POD}" -n "${NAMESPACE}" -- \
    kafka-console-consumer \
    --bootstrap-server "${BOOTSTRAP_INTERNAL}" \
    --topic "${TOPIC}" \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms $((TIMEOUT * 1000)) 2>&1 | grep -v "^Processed\|^$" || echo "")

if [[ -n "${CONSUMED}" ]]; then
    ok "메시지 수신 성공:"
    echo "   → ${CONSUMED}"
else
    fail "메시지 수신 실패 (${TIMEOUT}초 초과)"
fi

# ---- 7. Consumer Group 확인 ----
info "7. Consumer Group 목록..."
kubectl exec "${CLIENT_POD}" -n "${NAMESPACE}" -- \
    kafka-consumer-groups \
    --bootstrap-server "${BOOTSTRAP_INTERNAL}" \
    --list 2>&1 | sed 's/^/  /'
echo ""

# ---- 결과 요약 ----
echo "=============================================="
if [[ ${FAILED} -eq 0 ]]; then
    echo -e "${GREEN}  모든 테스트 통과${NC}"
else
    echo -e "${RED}  실패한 테스트: ${FAILED}건${NC}"
fi
echo "=============================================="
echo ""
echo "추가 테스트 명령어:"
echo "  # Pod 직접 접속"
echo "  kubectl exec -it ${CLIENT_POD} -n ${NAMESPACE} -- bash"
echo ""
echo "  # 실시간 메시지 구독"
echo "  kubectl exec -it ${CLIENT_POD} -n ${NAMESPACE} -- \\"
echo "    kafka-console-consumer --bootstrap-server ${BOOTSTRAP_INTERNAL} \\"
echo "    --topic ${TOPIC} --from-beginning"
echo ""
echo "  # 외부 bootstrap 주소"
echo "  kubectl get svc my-kafka-cluster-kafka-external-bootstrap -n ${NAMESPACE}"
