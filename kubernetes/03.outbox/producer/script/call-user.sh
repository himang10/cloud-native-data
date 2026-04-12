#!/bin/bash

NAME=${1:-"김철수"}
if [ -z "$NAME" ]; then
  echo "Usage: $0 <name>"
  exit 1
fi

EMAIL="${2:-kim@example.com}"
if [ -z "$EMAIL" ]; then
  echo "Usage: $0 <name> <email>"
  exit 1
fi

curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$NAME"'",
    "email": "'"$EMAIL"'"
  }' | jq .
