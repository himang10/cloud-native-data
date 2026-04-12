#!/bin/bash


ID=${1:-""}
if [ -z "$ID" ]; then
  echo "Usage: $0 <id>"
  exit 1
fi

NAME=${2:-"김철수"}

EMAIL="${3:-kim@example.com}"

curl -X PUT http://localhost:8080/api/users/$ID \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$NAME"'",
    "email": "'"$EMAIL"'"
  }' | jq .
