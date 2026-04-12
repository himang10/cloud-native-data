#!/bin/bash

CONTAINER_NAME="mariadb-cdc"
VOLUME_NAME="mariadb-data"

echo "경고: 이 스크립트는 MariaDB 컨테이너와 모든 데이터를 삭제합니다."
read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # 컨테이너 중지 및 삭제
    if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
        echo "컨테이너를 중지하고 삭제합니다..."
        docker stop ${CONTAINER_NAME} 2>/dev/null
        docker rm ${CONTAINER_NAME}
        echo "컨테이너가 삭제되었습니다."
    fi

    # 볼륨 삭제
    if docker volume inspect ${VOLUME_NAME} &> /dev/null; then
        echo "데이터 볼륨을 삭제합니다..."
        docker volume rm ${VOLUME_NAME}
        echo "볼륨이 삭제되었습니다."
    fi

    # 임시 파일 삭제
    rm -f /tmp/mariadb-custom.cnf
    rm -f /tmp/setup_debezium_user.sql

    echo ""
    echo "모든 MariaDB 리소스가 삭제되었습니다."
else
    echo "취소되었습니다."
fi
