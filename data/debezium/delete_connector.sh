#!/bin/bash
# chat-connector 를 지운다. debezium 파드 안의 curl 로 Kafka Connect REST(localhost:8083)를 부른다. 응답 HTTP 코드를 찍는다(204 = 지움, 404 = 없음).
#   data/debezium/delete_connector.sh          (NS=modu 기본)
set -eu
NS=${NS:-modu}

kubectl -n "$NS" exec deploy/debezium -- curl -s -o /dev/null -w '%{http_code}\n' -X DELETE http://localhost:8083/connectors/chat-connector
