#!/bin/bash

CONTAINER_NAME="kafka-connect-debezium"

echo "경고: 이 스크립트는 Kafka Connect 컨테이너를 삭제합니다."
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

    echo ""
    echo "Kafka Connect 컨테이너가 삭제되었습니다."
    echo "참고: Kafka 토픽의 데이터는 Kafka 클러스터에 남아있습니다."
else
    echo "취소되었습니다."
fi
