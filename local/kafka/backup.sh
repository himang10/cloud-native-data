#!/bin/bash

# 백업
docker run --rm \
  -v kafka-data:/data \
  -v $(pwd):/backup \
  ubuntu tar czf /backup/kafka-backup.tar.gz /data
