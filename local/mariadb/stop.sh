#!/bin/bash

CONTAINER_NAME="mariadb-cdc"

if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    echo "MariaDB 컨테이너를 중지합니다..."
    docker stop ${CONTAINER_NAME}
    echo "컨테이너가 중지되었습니다."
else
    echo "실행 중인 MariaDB 컨테이너가 없습니다."
fi
