#!/bin/bash

CLIENT_NAME="kafka-client"

# 클라이언트 컨테이너 확인 및 중지/삭제
if [ "$(docker ps -aq -f name=${CLIENT_NAME})" ]; then
    echo "Kafka 클라이언트 컨테이너를 중지하고 삭제합니다..."
    docker stop ${CLIENT_NAME}
    docker rm ${CLIENT_NAME}
    echo "클라이언트가 중지되었습니다."
else
    echo "실행 중인 클라이언트가 없습니다."
fi
