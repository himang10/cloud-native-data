#!/bin/bash

set -e

echo "=== Strimzi CRD 완전 삭제 ==="
echo "⚠️  경고: 아래 항목이 모두 삭제됩니다."
echo "   - Strimzi 관련 모든 CRD (Kafka, KafkaTopic, KafkaUser 등)"
echo "   - Strimzi ClusterRole / ClusterRoleBinding"
echo "   ※ kafka 네임스페이스는 삭제되지 않습니다."
echo ""
echo "이 작업은 되돌릴 수 없습니다."
echo ""

# 확인 프롬프트 (2단계)
read -r -p "정말로 삭제하시겠습니까? [y/N] " confirm1
if [[ ! "$confirm1" =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi
read -r -p "다시 한번 확인합니다. 모든 Kafka 데이터가 삭제됩니다. 계속합니까? [y/N] " confirm2
if [[ ! "$confirm2" =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

# 1. Strimzi Operator 먼저 중단 (새 Finalizer 추가 방지)
echo ""
echo "[1/4] Strimzi Operator 중단 중..."
kubectl scale deployment strimzi-cluster-operator -n kafka --replicas=0 2>&1 || true
sleep 3

# 2. 모든 Strimzi CR의 Finalizer 제거 (삭제 blocking 방지)
echo "[2/4] Finalizer 제거 중..."
for resource in kafka kafkanodepool kafkatopic kafkauser kafkaconnect kafkaconnector kafkamirrormaker2 kafkabridge kafkarebalance; do
    kubectl get "$resource" -n kafka -o name 2>/dev/null | while read name; do
        kubectl patch "$name" -n kafka -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        echo "  Finalizer 제거: $name"
    done
done

# 3. Kafka 클러스터 리소스 삭제
echo "[3/4] Kafka 클러스터 리소스 삭제 중..."
kubectl delete kafka,kafkanodepool,kafkatopic,kafkauser,kafkaconnect,kafkaconnector,kafkamirrormaker2,kafkabridge,kafkarebalance \
    --all -n kafka --ignore-not-found=true --wait=false 2>&1 || true

# 4. Strimzi Operator 및 RBAC 삭제
echo "[4/4] Strimzi Operator 삭제 중..."
kubectl delete -f "https://strimzi.io/install/latest?namespace=kafka" -n kafka \
    --ignore-not-found=true 2>&1 | grep -v "^Warning" || true
kubectl get crd -o name | grep "strimzi.io" | xargs -r kubectl delete --ignore-not-found=true 2>&1 || true

echo ""
echo "=== Strimzi CRD 삭제 완료 ==="
echo ""
echo "삭제 확인:"
echo "  kubectl get crd | grep strimzi         # 출력 없어야 함"
echo "  kubectl get clusterrole | grep strimzi  # 출력 없어야 함"
echo "  kubectl get all -n kafka               # Operator Pod 없어야 함"
