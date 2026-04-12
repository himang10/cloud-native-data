#!/usr/bin/env bash

set -euo pipefail

echo "================================================================"
echo " [Step 1] kafka-net 외부 네트워크 생성"
echo "================================================================"
bash "$(pwd)/01.create-kafka-net.sh"

echo ""
echo "================================================================"
echo " [Step 2] CDC 로컬 환경 기동 (kafka, kafka-connect, mariadb, pgvector)"
echo "================================================================"
docker compose -f "$(pwd)/docker-compose.yaml" up --build -d

echo ""
echo "================================================================"
echo " [Step 3] Conduktor 플랫폼 기동"
echo "================================================================"
docker compose -f "$(pwd)/conduktor/docker-compose.yaml" up -d

echo ""
echo "================================================================"
echo " 모든 서비스가 정상적으로 기동되었습니다."
echo "   Kafka            : localhost:9094"
echo "   Kafka Connect    : http://localhost:8083"
echo "   Debezium UI      : http://localhost:8088"
echo "   MariaDB          : localhost:3306"
echo "   PostgreSQL       : localhost:5433"
echo "   Conduktor        : http://localhost:38080"
echo "================================================================"
