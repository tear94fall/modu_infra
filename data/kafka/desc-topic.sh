#!/bin/bash
# 토픽 상세(파티션·리더·ISR). kafka-0 파드 안의 kafka-topics 를 kubectl exec 로 부른다.
#   data/kafka/desc-topic.sh <topic>          (NS=modu 기본)
set -eu
NS=${NS:-modu}

topic=${1:-}
if [ -z "$topic" ]; then
  echo "사용: data/kafka/desc-topic.sh <topic>" >&2
  exit 2
fi

kubectl -n "$NS" exec kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --describe --topic "$topic"
