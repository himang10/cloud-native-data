#!/bin/bash
# PostgreSQL 외부 접속 진단 스크립트

echo "=== PostgreSQL 외부 접속 진단 시작 ==="
echo "Timestamp: $(date)"
echo

# 1. Service 정보 확인
echo "1. Service 정보 확인"
echo "===================="
kubectl get svc -l app.kubernetes.io/name=postgresql -o wide
echo

# 2. LoadBalancer IP 확인
echo "2. LoadBalancer IP 확인"
echo "======================"
SERVICE_NAME="postgres-1-postgresql-lb"
EXTERNAL_IP=$(kubectl get svc $SERVICE_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
EXTERNAL_HOSTNAME=$(kubectl get svc $SERVICE_NAME -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Service Name: $SERVICE_NAME"
echo "External IP: $EXTERNAL_IP"
echo "External Hostname: $EXTERNAL_HOSTNAME"
echo

# 3. Pod 상태 확인
echo "3. Pod 상태 확인"
echo "==============="
kubectl get pods -l app.kubernetes.io/name=postgresql -o wide
echo

# 4. Endpoints 확인
echo "4. Endpoints 확인"
echo "================"
kubectl get endpoints $SERVICE_NAME
echo

# 5. PostgreSQL 설정 확인
echo "5. PostgreSQL 설정 확인"
echo "======================"
POD_NAME=$(kubectl get pods -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')
echo "Pod Name: $POD_NAME"

echo "--- listen_addresses 확인 ---"
kubectl exec $POD_NAME -- psql -U postgres -c "SHOW listen_addresses;"

echo "--- port 확인 ---"
kubectl exec $POD_NAME -- psql -U postgres -c "SHOW port;"

echo "--- max_connections 확인 ---"
kubectl exec $POD_NAME -- psql -U postgres -c "SHOW max_connections;"

echo

# 6. pg_hba.conf 확인
echo "6. pg_hba.conf 확인"
echo "=================="
kubectl exec $POD_NAME -- cat /opt/bitnami/postgresql/conf/pg_hba.conf
echo

# 7. 네트워크 연결 테스트
echo "7. 네트워크 연결 테스트"
echo "====================="
if [ ! -z "$EXTERNAL_IP" ]; then
    echo "External IP로 포트 연결 테스트..."
    nc -zv $EXTERNAL_IP 5432 || echo "포트 5432 연결 실패"
elif [ ! -z "$EXTERNAL_HOSTNAME" ]; then
    echo "External Hostname으로 포트 연결 테스트..."
    nc -zv $EXTERNAL_HOSTNAME 5432 || echo "포트 5432 연결 실패"
else
    echo "External IP/Hostname이 할당되지 않음"
fi
echo

# 8. LoadBalancer 상세 정보
echo "8. LoadBalancer 상세 정보"
echo "========================"
kubectl describe svc $SERVICE_NAME
echo

# 9. PostgreSQL 로그 확인
echo "9. PostgreSQL 로그 (최근 50줄)"
echo "============================="
kubectl logs $POD_NAME --tail=50
echo

# 10. 연결 테스트 명령어 제공
echo "10. 연결 테스트 명령어"
echo "===================="
if [ ! -z "$EXTERNAL_IP" ]; then
    echo "psql -h $EXTERNAL_IP -p 5432 -U postgres -d postgres"
    echo "psql -h $EXTERNAL_IP -p 5432 -U skala -d cloud"
elif [ ! -z "$EXTERNAL_HOSTNAME" ]; then
    echo "psql -h $EXTERNAL_HOSTNAME -p 5432 -U postgres -d postgres"
    echo "psql -h $EXTERNAL_HOSTNAME -p 5432 -U skala -d cloud"
else
    echo "LoadBalancer IP가 할당되지 않음. 클라우드 환경을 확인하세요."
fi
echo

echo "=== 진단 완료 ==="
