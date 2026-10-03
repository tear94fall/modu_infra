#!/bin/bash
# 토픽 생성. kafka-0 파드 안의 kafka-topics 를 kubectl exec 로 부른다(브로커 1대라 replication factor 는 1).
#   data/kafka/create-topic.sh <topic> <partitions>          (NS=modu 기본)
set -eu
NS=${NS:-modu}

topic=${1:-}
partition=${2:-}
if [ -z "$topic" ] || [ -z "$partition" ]; then
  echo "사용: data/kafka/create-topic.sh <topic> <partitions>" >&2
  exit 2
fi

kubectl -n "$NS" exec kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --create --topic "$topic" --partitions "$partition"
