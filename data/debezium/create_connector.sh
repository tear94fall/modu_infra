#!/bin/bash
# mysql-chat 의 modu-chat.chat 테이블 CDC 커넥터(chat-connector)를 등록한다. debezium 파드 안의 curl 로 Kafka Connect REST(localhost:8083)를 부른다.
# DB 는 클러스터 안 Service mysql-chat:3306, 비밀번호는 Secret infra 의 MYSQL_ROOT_PASSWORD(JSON 본문을 stdin 으로 넘기므로 명령줄엔 안 보인다).
#   data/debezium/create_connector.sh          (NS=modu 기본)
set -euo pipefail
NS=${NS:-modu}

MYSQL_ROOT_PASSWORD=$(kubectl -n "$NS" get secret infra -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d)
[ -n "$MYSQL_ROOT_PASSWORD" ] || { echo "Secret infra 에 MYSQL_ROOT_PASSWORD 가 없다" >&2; exit 1; }

kubectl -n "$NS" exec -i deploy/debezium -- curl -s -X POST --header 'Content-Type: application/json' --data-binary @- http://localhost:8083/connectors <<JSON | python3 -m json.tool
{
    "name": "chat-connector",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "database.allowPublicKeyRetrieval":"true",
        "database.hostname": "mysql-chat",
        "database.port": "3306",
        "database.user": "root",
        "database.password": "${MYSQL_ROOT_PASSWORD}",
        "database.include.list": "modu-chat",
        "table.include.list": "modu-chat.chat",
        "topic.prefix": "modu",
        "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
        "schema.history.internal.kafka.topic": "schema-changes.db",
        "database.server.id": 1,
        "transforms": "createdAt",
        "transforms.createdAt.type": "org.apache.kafka.connect.transforms.TimestampConverter\$Value",
        "transforms.createdAt.target.type": "string",
        "transforms.createdAt.field": "created_date",
        "transforms.createdAt.format": "yyyy-MM-dd HH:mm:ss",
        "time.precision.mode": "connect",
        "snapshot.mode": "when_needed"
    }
}
JSON
