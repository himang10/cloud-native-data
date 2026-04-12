#!/bin/bash
################################################################################
# Consumer 애플리케이션 테스트 스크립트
################################################################################

set -e

NAMESPACE="kafka"
APP_NAME="outbox-consumer"
TOPIC_NAME="outbox.user"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Consumer 애플리케이션 테스트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. Consumer Pod 확인
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 1: Consumer Pod 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME" -o jsonpath='{.items[*].metadata.name}')

if [ -z "$PODS" ]; then
    echo " Consumer Pod를 찾을 수 없습니다."
    echo ""
    echo "Consumer가 배포되지 않았을 수 있습니다."
    echo "   배포 확인: kubectl get deployment -n $NAMESPACE -l app=$APP_NAME"
    echo ""
    echo "대신 Kafka Consumer로 직접 메시지 확인:"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Kafka Consumer로 메시지 확인"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    kubectl run kafka-test-consumer --rm -i --restart=Never \
        --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
        --namespace="$NAMESPACE" \
        --command -- timeout 15s /opt/kafka/bin/kafka-console-consumer.sh \
        --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092 \
        --topic "$TOPIC_NAME" \
        --from-beginning \
        --max-messages 5 \
        --property print.headers=true \
        --property print.timestamp=true \
        --property print.key=true 2>/dev/null || echo "완료"

    echo ""
    echo "메시지 확인 완료 (Consumer Pod 없이 테스트)"
    exit 0
fi

POD_ARRAY=($PODS)
POD_NAME="${POD_ARRAY[0]}"

echo "Consumer Pod 발견: $POD_NAME"

# 2. Pod 상태 확인
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 2: Pod 상태 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

kubectl get pod "$POD_NAME" -n "$NAMESPACE"

POD_STATUS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
    echo ""
    echo " Pod가 Running 상태가 아닙니다: $POD_STATUS"
    echo ""
    echo "Pod 이벤트:"
    kubectl describe pod "$POD_NAME" -n "$NAMESPACE" | grep -A 20 Events:
    exit 1
fi

echo "Pod가 Running 상태입니다"

# 3. Consumer 로그 확인
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 3: Consumer 로그 확인 (최근 50줄)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=50

# 4. Kafka 연결 상태 확인
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 4: Kafka 연결 상태 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

KAFKA_LOGS=$(kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=100 | grep -i "kafka\|consumer\|partition" | head -10 || echo "")

if [ ! -z "$KAFKA_LOGS" ]; then
    echo "Kafka 관련 로그:"
    echo "$KAFKA_LOGS"
else
    echo " Kafka 관련 로그를 찾을 수 없습니다"
fi

# 5. USER 이벤트 처리 로그 확인
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 5: USER 이벤트 처리 로그"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

USER_LOGS=$(kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=200 | grep -i "user\|outbox.USER\|테스트사용자" || echo "")

if [ -z "$USER_LOGS" ]; then
    echo " USER 이벤트 처리 로그를 찾을 수 없습니다"
    echo ""
    echo "가능한 원인:"
    echo "   1. Consumer가 아직 메시지를 받지 못했습니다"
    echo "   2. Consumer가 다른 토픽을 구독하고 있습니다"
    echo "   3. Consumer Group에 문제가 있습니다"
    echo ""
    echo "Consumer 설정 확인:"
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- env | grep -i "kafka\|spring" | grep -v PASSWORD || echo "환경 변수 확인 실패"
else
    echo "USER 이벤트 처리 로그 발견:"
    echo "$USER_LOGS"
fi

# 6. 에러 로그 확인
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 6: 에러 로그 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ERROR_LOGS=$(kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=100 | grep -i "error\|exception\|failed" || echo "")

if [ -z "$ERROR_LOGS" ]; then
    echo "에러 로그 없음"
else
    echo " 에러 로그 발견:"
    echo "$ERROR_LOGS"
fi

# 7. Consumer Group 정보
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 7: Kafka Consumer Group 상태"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CONSUMER_GROUP="outbox-consumer-group"

echo "Consumer Group: $CONSUMER_GROUP"
kubectl run kafka-consumer-group-check --rm -i --restart=Never \
    --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
    --namespace="$NAMESPACE" \
    --command -- /opt/kafka/bin/kafka-consumer-groups.sh \
    --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092 \
    --describe \
    --group "$CONSUMER_GROUP" 2>/dev/null || echo "Consumer Group 정보를 가져올 수 없습니다"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Consumer 테스트 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "실시간 로그 모니터링:"
echo "   kubectl logs -n $NAMESPACE -f $POD_NAME"
echo ""
echo "PostgreSQL 데이터 확인 (Consumer가 저장하는 경우):"
echo "   kubectl exec -n <postgresql-namespace> <postgresql-pod> -- psql -U skala -d cloud -c 'SELECT * FROM user_summary ORDER BY created_at DESC LIMIT 5;'"

