#!/bin/bash

# DDL 파싱 에러 해결을 위한 종합 스크립트

echo "=== Debezium Outbox Connector DDL Error Fix ==="

# 1. Database 제약조건 수정 (선택사항)
echo "1. Checking if database constraints need to be fixed..."
read -p "Do you want to run the database constraint fix script? (y/n): " run_db_fix

if [ "$run_db_fix" = "y" ] || [ "$run_db_fix" = "Y" ]; then
    echo "Please run the following SQL script manually in your MariaDB:"
    echo "mysql -h a1961fab471c6487aa7b3f049f61cdf7-770154099.ap-northeast-2.elb.amazonaws.com -u skala -p cloud < /Users/himang10/mydev/skala/ywyi-skala-edu-code/eks/kafka-cluster/outbox/sql/02-fix-table-constraints.sql"
    echo ""
    read -p "Press Enter after running the SQL script..."
fi

# 2. Producer 재시작 (Hibernate DDL 설정 변경 반영)
echo "2. Restarting producer to apply Hibernate DDL changes..."
read -p "Do you want to restart the producer application? (y/n): " restart_producer

if [ "$restart_producer" = "y" ] || [ "$restart_producer" = "Y" ]; then
    echo "Please restart your producer application with the updated Hibernate settings."
    echo "The DDL auto-generation has been disabled to prevent conflicts with Debezium."
fi

# 3. 기존 커넥터 삭제
echo "3. Deleting existing connector..."
kubectl delete kafkaconnector mariadb-outbox-connector-v2 -n kafka --ignore-not-found=true

# 4. 잠시 대기
echo "4. Waiting for connector deletion..."
sleep 10

# 5. 새 커넥터 배포
echo "5. Deploying updated connector with DDL error handling..."
kubectl apply -f /Users/himang10/mydev/skala/ywyi-skala-edu-code/eks/kafka-cluster/outbox/connectors/mariadb-outbox-connector.yaml

# 6. 커넥터 상태 확인
echo "6. Checking connector status..."
sleep 5
kubectl get kafkaconnector mariadb-outbox-connector-v2 -n kafka

echo ""
echo "=== Fix Summary ==="
echo "Hibernate DDL auto-generation disabled (ddl-auto: none/validate)"
echo "Debezium connector configured to skip DDL parsing errors"
echo "Error tolerance set to 'all' with dead letter queue"
echo "DDL operations skipping enabled"
echo ""
echo "=== Monitoring Commands ==="
echo "Check connector logs:"
echo "kubectl logs -f deployment/debezium-source-connect-connect -n kafka"
echo ""
echo "Check connector status:"
echo "kubectl get kafkaconnector mariadb-outbox-connector-v2 -n kafka -o yaml"
echo ""
echo "Check error topic (if any):"
echo "kubectl exec -it my-kafka-cluster-kafka-0 -n kafka -- kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic outbox-connector-errors --from-beginning"