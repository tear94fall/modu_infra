#!/bin/sh
# 스키마 기준선(baseline)을 소스 DB 에서 떠서 mysql/schema/<instance>.<schema>.sql 로 저장한다. 데이터는 없다.
# 변경을 적용한 뒤 항상 다시 떠서 변경 SQL(schema/changes/)과 같은 PR 에 넣는다 — 기준선이 "지금 운영 DB 모양"이다.
#
#   sh mysql/dump-schema.sh            # 전부
#   sh mysql/dump-schema.sh commerce   # 하나만 (member | chat | push | profile | commerce)
#
# AUTO_INCREMENT 값은 지워서(데이터에 따라 변하는 값) diff 가 스키마 변화만 보여주게 한다.
set -eu
cd "$(dirname "$0")"
set -a; . ../.env; set +a

dump() { # $1 instance  $2 root 비밀번호  $3 schema
  out="schema/$1.$3.sql"
  {
    echo "-- 스키마 기준선: mysql-$1 / \`$3\`  (sh mysql/dump-schema.sh $1 로 생성, 데이터 없음)"
    docker exec -e MYSQL_PWD="$2" "mysql-$1" \
      mysqldump -uroot --no-data --set-gtid-purged=OFF --skip-comments --skip-add-drop-table --routines --triggers --events "$3" 2>/dev/null \
      | sed -E 's/ AUTO_INCREMENT=[0-9]+//'
  } > "$out"
  echo "== $out ($(grep -c '^CREATE TABLE' "$out") tables)"
}

for t in ${*:-member chat push profile commerce}; do
  case "$t" in
    member)   for s in modu-chat modu-point modu-schedule; do dump member "${MYSQL_ROOT_PASSWORD:?}" "$s"; done ;;
    chat|push|profile) dump "$t" "${MYSQL_ROOT_PASSWORD:?}" modu-chat ;;
    commerce) dump commerce "${COMMERCE_DB_PASSWORD:?}" commerce ;;
    *) echo "사용: sh mysql/dump-schema.sh [member|chat|push|profile|commerce ...]" >&2; exit 2 ;;
  esac
done
