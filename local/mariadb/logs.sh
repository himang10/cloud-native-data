#!/bin/bash

CONTAINER_NAME="mariadb-cdc"

if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    echo "MariaDB 로그를 확인합니다 (Ctrl+C로 종료)..."
    echo ""
    docker logs -f ${CONTAINER_NAME}
else
    echo "실행 중인 MariaDB 컨테이너가 없습니다."
    echo ""
    echo "마지막 로그 확인:"
    docker logs ${CONTAINER_NAME} 2>/dev/null || echo "로그가 없습니다."
fi
