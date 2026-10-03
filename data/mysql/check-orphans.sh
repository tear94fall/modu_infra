#!/bin/sh
# 고아 행 점검(schema/checks/orphans.sql)을 레플리카 파드(mysql-<instance>-replica-0)에서 돌린다.
# orphans 가 0 이 아닌 줄만 출력하고, 있으면 종료 코드 1.
#   sh data/mysql/check-orphans.sh        # 조용히 — 문제 있는 짝만   (NS=modu 기본)
#   sh data/mysql/check-orphans.sh -v     # 전부 출력
#
# root 비밀번호는 파드 env MYSQL_ROOT_PASSWORD 를 파드 안에서만 쓴다(커머스 파드엔 COMMERCE_DB_PASSWORD 가 그 이름으로 들어 있다).
set -eu
NS=${NS:-modu}
cd "$(dirname "$0")"
VERBOSE=${1:-}
bad=0
instance=""; schema=""
while IFS= read -r line; do
  case "$line" in
    "-- @ "*) set -- $line; instance=$3; schema=$4; continue ;;
    SELECT*) ;;
    *) continue ;;
  esac
  # 레플리카에서 읽는다(운영 소스에 부하를 주지 않는다). 레플리카가 없으면 소스로 바꾼다.
  out=$(kubectl -n "$NS" exec "mysql-$instance-replica-0" -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -e "$1" "$2"' sh "$line" "$schema" </dev/null)
  n=$(echo "$out" | awk '{print $NF}')
  if [ "$n" != "0" ]; then echo "!! $instance/$schema  $out"; bad=1
  elif [ "$VERBOSE" = "-v" ]; then echo "   $instance/$schema  $out"; fi
done < schema/checks/orphans.sql
[ "$bad" = 0 ] && echo "고아 행 없음" || exit 1
