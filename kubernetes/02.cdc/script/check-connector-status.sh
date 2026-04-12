#!/bin/bash

# Kafka Connector 상태 확인 스크립트
# 사용법: ./check-connector-status.sh [connector-name]

set -e

NAMESPACE="kafka"
CONNECTOR_NAME=${1:-"mariadb-source-cdc-connector-v1.0.0"}

echo "=========================================="
echo " Kafka Connector 상태 확인"
echo "=========================================="
echo ""
echo " Connector: $CONNECTOR_NAME"
echo " Namespace: $NAMESPACE"
echo ""

# 1. Connector 목록 조회
echo ""
echo " 등록된 Connector 목록"
echo ""
echo ""

kubectl get kafkaconnector -n $NAMESPACE

echo ""

# 2. 특정 Connector 상세 상태
if kubectl get kafkaconnector $CONNECTOR_NAME -n $NAMESPACE &>/dev/null; then
    echo ""
    echo " Connector 상세 상태"
    echo ""
    echo ""
    
    # 기본 정보
    echo " 기본 정보:"
    kubectl get kafkaconnector $CONNECTOR_NAME -n $NAMESPACE -o jsonpath='
    Connector Name: {.metadata.name}
    Cluster: {.spec.class}
    Max Tasks: {.spec.tasksMax}
    Ready: {.status.conditions[?(@.type=="Ready")].status}
    ' 2>/dev/null || echo "  정보 조회 실패"
    echo ""
    echo ""
    
    # Connector 상태
    echo " Connector 상태:"
    kubectl get kafkaconnector $CONNECTOR_NAME -n $NAMESPACE -o jsonpath='
    State: {.status.connectorStatus.connector.state}
    Worker ID: {.status.connectorStatus.connector.worker_id}
    ' 2>/dev/null || echo "  상태 조회 실패"
    echo ""
    echo ""
    
    # Task 상태
    echo " Task 상태:"
    kubectl get kafkaconnector $CONNECTOR_NAME -n $NAMESPACE -o json | \
        jq -r '.status.connectorStatus.tasks[]? | "  Task \(.id): \(.state) (\(.worker_id))"' 2>/dev/null || \
        echo "  Task 정보 없음"
    echo ""
    
    # Topics
    echo " 관련 Topics:"
    kubectl get kafkaconnector $CONNECTOR_NAME -n $NAMESPACE -o json | \
        jq -r '.status.topics[]? | "  - \(.)"' 2>/dev/null || \
        echo "  Topic 정보 없음"
    echo ""
    
    # 상태 체크
    CONNECTOR_STATE=$(kubectl get kafkaconnector $CONNECTOR_NAME -n $NAMESPACE -o jsonpath='{.status.connectorStatus.connector.state}' 2>/dev/null)
    
    echo ""
    if [ "$CONNECTOR_STATE" = "RUNNING" ]; then
        echo " Connector가 정상 동작 중입니다!"
    elif [ "$CONNECTOR_STATE" = "FAILED" ]; then
        echo " Connector가 실패 상태입니다!"
        echo ""
        echo " 로그 확인이 필요합니다:"
        echo "  kubectl logs -n kafka debezium-connect-cluster-connect-0 --tail=100"
    else
        echo "  Connector 상태: $CONNECTOR_STATE"
    fi
    echo ""
    echo ""
    
    # 상세 정보 (YAML)
    echo " 전체 상세 정보 보기:"
    echo "  kubectl describe kafkaconnector $CONNECTOR_NAME -n $NAMESPACE"
    echo ""
    
else
    echo " Connector '$CONNECTOR_NAME'를 찾을 수 없습니다."
    echo ""
    echo " 사용 가능한 Connector 목록:"
    kubectl get kafkaconnector -n $NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "  없음"
    echo ""
fi

echo "=========================================="
echo " 추가 명령어"
echo "=========================================="
echo ""
echo "# Connector 재시작"
echo "kubectl delete kafkaconnector $CONNECTOR_NAME -n $NAMESPACE"
echo "kubectl apply -f mariadb-source-connector.yaml"
echo ""
echo "# Connector 로그 확인"
echo "kubectl logs -n kafka debezium-connect-cluster-connect-0 --tail=200"
echo ""
echo "# Connect Cluster 상태"
echo "kubectl get kafkaconnect -n kafka"
echo ""

