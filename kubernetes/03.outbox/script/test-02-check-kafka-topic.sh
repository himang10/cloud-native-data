#!/bin/bash
################################################################################
# Kafka 토픽 생성 및 메시지 형식 확인 스크립트
################################################################################

set -e

KAFKA_NAMESPACE="kafka"
KAFKA_CLUSTER="my-kafka-cluster"
TOPIC_NAME="outbox.user"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Kafka 토픽 및 메시지 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "확인 대상 토픽: $TOPIC_NAME"
echo ""

# 1. Kafka 클러스터 상태 확인
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 1: Kafka 클러스터 상태 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

KAFKA_READY=$(kubectl get kafka "$KAFKA_CLUSTER" -n "$KAFKA_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

if [ "$KAFKA_READY" != "True" ]; then
    echo " Kafka 클러스터가 준비되지 않았습니다."
    exit 1
fi
echo "Kafka 클러스터 정상 동작 중"

# 2. 토픽 목록 확인
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 2: Outbox 관련 토픽 목록 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "전체 Outbox 토픽:"
kubectl run kafka-list-topics-temp --rm -i --restart=Never \
    --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
    --namespace="$KAFKA_NAMESPACE" \
    --command -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "${KAFKA_CLUSTER}-kafka-bootstrap:9092" \
    --list 2>/dev/null | grep -i outbox || echo "   (outbox 토픽 없음)"

# 3. 특정 토픽 존재 확인
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 3: $TOPIC_NAME 토픽 존재 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TOPIC_EXISTS=$(kubectl run kafka-check-topic-temp --rm -i --restart=Never \
    --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
    --namespace="$KAFKA_NAMESPACE" \
    --command -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "${KAFKA_CLUSTER}-kafka-bootstrap:9092" \
    --list 2>/dev/null | grep "^${TOPIC_NAME}$" || echo "")

if [ -z "$TOPIC_EXISTS" ]; then
    echo "토픽 '$TOPIC_NAME'이 존재하지 않습니다."
    echo ""
    echo "가능한 원인:"
    echo "   1. Debezium Connector가 아직 이벤트를 처리하지 않았습니다"
    echo "   2. Connector에 문제가 있습니다"
    echo ""
    echo "Connector 상태 확인:"
    kubectl get kafkaconnector mariadb-outbox-cloudevents-connector -n "$KAFKA_NAMESPACE"
    exit 1
fi

echo "토픽 '$TOPIC_NAME'이 존재합니다"

# 4. 토픽 상세 정보
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 4: 토픽 상세 정보"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

kubectl run kafka-describe-topic-temp --rm -i --restart=Never \
    --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
    --namespace="$KAFKA_NAMESPACE" \
    --command -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "${KAFKA_CLUSTER}-kafka-bootstrap:9092" \
    --describe \
    --topic "$TOPIC_NAME" 2>/dev/null

# 5. 메시지 확인 및 형식 분석
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 5: 메시지 확인 및 형식 분석"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "최근 메시지 (최대 3개):"
echo ""

MESSAGES=$(kubectl run kafka-consume-temp --rm -i --restart=Never \
    --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
    --namespace="$KAFKA_NAMESPACE" \
    --command -- timeout 10s /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server "${KAFKA_CLUSTER}-kafka-bootstrap:9092" \
    --topic "$TOPIC_NAME" \
    --from-beginning \
    --max-messages 3 \
    --property print.headers=true \
    --property print.timestamp=true \
    --property print.key=true 2>/dev/null || echo "")

if [ -z "$MESSAGES" ]; then
    echo " 메시지가 없습니다."
    echo ""
    echo "확인 사항:"
    echo "   1. Debezium이 이벤트를 처리했는지 확인"
    echo "   2. Connector 로그 확인:"
    echo "      kubectl logs -n kafka -l strimzi.io/cluster=debezium-source-connect --tail=50"
    exit 1
fi

echo "$MESSAGES"
echo ""

# 6. 메시지 형식 분석
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "단계 6: 메시지 형식 분석"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 첫 번째 메시지만 가져와서 분석
FIRST_MESSAGE=$(kubectl run kafka-consume-single --rm -i --restart=Never \
    --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
    --namespace="$KAFKA_NAMESPACE" \
    --command -- timeout 5s /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server "${KAFKA_CLUSTER}-kafka-bootstrap:9092" \
    --topic "$TOPIC_NAME" \
    --from-beginning \
    --max-messages 1 2>/dev/null | tail -1 || echo "")

if [ ! -z "$FIRST_MESSAGE" ]; then
    echo "메시지 본문:"
    echo "$FIRST_MESSAGE" | python3 -m json.tool 2>/dev/null || echo "$FIRST_MESSAGE"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "CloudEvents 형식 확인"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # CloudEvents 필수 필드 확인
    HAS_SPECVERSION=$(echo "$FIRST_MESSAGE" | grep -o '"specversion"' || echo "")
    HAS_ID=$(echo "$FIRST_MESSAGE" | grep -o '"id"' || echo "")
    HAS_SOURCE=$(echo "$FIRST_MESSAGE" | grep -o '"source"' || echo "")
    HAS_TYPE=$(echo "$FIRST_MESSAGE" | grep -o '"type"' || echo "")
    
    if [ ! -z "$HAS_SPECVERSION" ] && [ ! -z "$HAS_ID" ] && [ ! -z "$HAS_SOURCE" ] && [ ! -z "$HAS_TYPE" ]; then
        echo "CloudEvents 형식입니다!"
        echo "   - specversion: 있음"
        echo "   - id: 있음"
        echo "   - source: 있음"
        echo "   - type: 있음"
    else
        echo "CloudEvents 형식이 아닙니다 (표준 Outbox 형식)"
        echo "   현재 Connector: mariadb-outbox-connector (기본 Outbox)"
        echo "   CloudEvents 사용하려면: mariadb-outbox-cloudevents-connector 사용"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Kafka 토픽 확인 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "다음 단계: Consumer 테스트"
echo "           ./test-03-test-consumer.sh"

