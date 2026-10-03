#!/bin/bash
# 등록된 커넥터 목록. debezium 파드 안의 curl 로 Kafka Connect REST(localhost:8083)를 부른다(8083 은 바깥에 안 열려 있다).
#   data/debezium/list_connector.sh          (NS=modu 기본)
set -eu
NS=${NS:-modu}

kubectl -n "$NS" exec deploy/debezium -- curl -s -X GET -H "Accept:application/json" -H "Content-Type:application/json" http://localhost:8083/connectors/ \
  | python3 -m json.tool
