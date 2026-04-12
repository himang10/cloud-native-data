# 커넥터 목록
curl -s http://localhost:8083/connectors | jq

# 상태
curl -s http://localhost:8083/connectors/mariadb-source-cdc-connector/status | jq

# 설정 읽기
curl -s http://localhost:8083/connectors/mariadb-source-cdc-connector | jq

# 설정 수정(전체 치환 PUT)
curl -s -X PUT http://localhost:8083/connectors/mariadb-source-cdc-connector/config \
  -H "Content-Type: application/json" \
  -d @connector-config.json | jq

# 삭제
curl -s -X DELETE http://localhost:8083/connectors/mariadb-source-cdc-connector | jq

