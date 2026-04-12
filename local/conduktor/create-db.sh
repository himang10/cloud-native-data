#!/bin/bash

# pgvector 컨테이너에 접속해서 conduktor 데이터베이스 생성
docker exec -it pgvector psql -U postgres -c "CREATE DATABASE conduktor;"

# 데이터베이스 생성 확인
docker exec -it pgvector psql -U postgres -c "\l"
