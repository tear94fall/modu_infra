#!/bin/sh
# 고아 행 점검(schema/checks/orphans.sql)을 레플리카에서 돌린다. orphans 가 0 이 아닌 줄만 출력하고, 있으면 종료 코드 1.
#   sh mysql/check-orphans.sh        # 조용히 — 문제 있는 짝만
#   sh mysql/check-orphans.sh -v     # 전부 출력
set -eu
cd "$(dirname "$0")"
set -a; . ../.env; set +a
VERBOSE=${1:-}
bad=0
instance=""; schema=""
pw() { case "$1" in commerce) echo "${COMMERCE_DB_PASSWORD:?}";; *) echo "${MYSQL_ROOT_PASSWORD:?}";; esac; }
while IFS= read -r line; do
  case "$line" in
    "-- @ "*) set -- $line; instance=$3; schema=$4; continue ;;
    SELECT*) ;;
    *) continue ;;
  esac
  # 레플리카에서 읽는다(운영 소스에 부하를 주지 않는다). 레플리카가 없으면 소스로 바꾼다.
  out=$(docker exec -e MYSQL_PWD="$(pw "$instance")" "mysql-$instance-replica" mysql -uroot -N -e "$line" "$schema")
  n=$(echo "$out" | awk '{print $NF}')
  if [ "$n" != "0" ]; then echo "!! $instance/$schema  $out"; bad=1
  elif [ "$VERBOSE" = "-v" ]; then echo "   $instance/$schema  $out"; fi
done < schema/checks/orphans.sql
[ "$bad" = 0 ] && echo "고아 행 없음" || exit 1
