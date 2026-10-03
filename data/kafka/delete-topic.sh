#!/bin/bash
# 토픽 삭제. kafka-0 파드 안의 kafka-topics 를 kubectl exec 로 부른다. 되돌릴 수 없다.
#   data/kafka/delete-topic.sh <topic>          (NS=modu 기본)
set -eu
NS=${NS:-modu}

topic=${1:-}
if [ -z "$topic" ]; then
  echo "사용: data/kafka/delete-topic.sh <topic>" >&2
  exit 2
fi

kubectl -n "$NS" exec kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --delete --topic "$topic"
