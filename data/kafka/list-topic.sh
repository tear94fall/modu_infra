#!/bin/bash
# 토픽 목록. kafka-0 파드 안의 kafka-topics 를 kubectl exec 로 부른다(브로커는 바깥에 안 열려 있다).
#   data/kafka/list-topic.sh          (NS=modu 기본)
set -eu
NS=${NS:-modu}

kubectl -n "$NS" exec kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --list
