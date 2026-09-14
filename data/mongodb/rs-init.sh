#!/bin/bash
# replica set 최초 구성. mongo-01 컨테이너 안에서 실행한다: docker exec mongo-01 bash /scripts/rs-init.sh
# 이미 구성된 replica set 에서 실행하면 force 로 설정을 덮어쓰므로 최초 1회만 쓴다.

mongosh -u admin -p "$MONGO_INITDB_ROOT_PASSWORD" <<EOF
var config = {
    "_id": "mongo-rs",
    "version": 1,
    "members": [
        {
            "_id": 1,
            "host": "mongo-01:27017",
            "priority": 3
        },
        {
            "_id": 2,
            "host": "mongo-02:27017",
            "priority": 2
        },
        {
            "_id": 3,
            "host": "mongo-03:27017",
            "priority": 1
        }
    ]
};
rs.initiate(config, { force: true });
rs.status();

EOF
