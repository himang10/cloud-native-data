#!/bin/bash

docker run -it --rm --name debezium-ui \
  -p 8088:8080 \
  -e KAFKA_CONNECT_URIS=http://connect:8083 \
  quay.io/debezium/debezium-ui:2.5
