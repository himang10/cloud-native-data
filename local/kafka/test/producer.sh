#!/bin/bash

docker exec -it kafka kafka-console-producer.sh \
  --topic test-topic \
  --bootstrap-server localhost:9092
