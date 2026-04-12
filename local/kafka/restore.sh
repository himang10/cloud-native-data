#!/bin/bash

# 복원
docker run --rm \
  -v kafka-data:/data \
  -v $(pwd):/backup \
  ubuntu tar xzf /backup/kafka-backup.tar.gz -C /
