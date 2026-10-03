#!/bin/sh
# 스키마 기준선(baseline)을 소스 DB(파드 mysql-<instance>-0)에서 떠서 mysql/schema/<instance>.<schema>.sql 로 저장한다. 데이터는 없다.
# 변경을 적용한 뒤 항상 다시 떠서 변경 SQL(schema/changes/)과 같은 PR 에 넣는다 — 기준선이 "지금 운영 DB 모양"이다.
#
#   sh data/mysql/dump-schema.sh            # 전부                  (NS=modu 기본)
#   sh data/mysql/dump-schema.sh commerce   # 하나만 (member | chat | push | profile | commerce)
#   OUT_DIR=/tmp/schema sh data/mysql/dump-schema.sh   # 저장소 대신 다른 디렉터리로(비교용)
#
# root 비밀번호는 파드 env MYSQL_ROOT_PASSWORD 를 파드 안에서만 쓴다.
# AUTO_INCREMENT 값은 지워서(데이터에 따라 변하는 값) diff 가 스키마 변화만 보여주게 한다.
set -eu
NS=${NS:-modu}
cd "$(dirname "$0")"
OUT_DIR=${OUT_DIR:-schema}
mkdir -p "$OUT_DIR"

dump() { # $1 instance  $2 schema
  out="$OUT_DIR/$1.$2.sql"
  {
    echo "-- 스키마 기준선: mysql-$1 / \`$2\`  (sh mysql/dump-schema.sh $1 로 생성, 데이터 없음)"
    kubectl -n "$NS" exec "mysql-$1-0" -- sh -c \
      'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot --no-data --set-gtid-purged=OFF --skip-comments --skip-add-drop-table --routines --triggers --events "$1" 2>/dev/null' \
      sh "$2" \
      | sed -E 's/ AUTO_INCREMENT=[0-9]+//'
  } > "$out"
  echo "== $out ($(grep -c '^CREATE TABLE' "$out") tables)"
}

for t in ${*:-member chat push profile commerce}; do
  case "$t" in
    member)   for s in modu-chat modu-point modu-schedule; do dump member "$s"; done ;;
    chat|push|profile) dump "$t" modu-chat ;;
    commerce) dump commerce commerce ;;
    *) echo "사용: sh data/mysql/dump-schema.sh [member|chat|push|profile|commerce ...]" >&2; exit 2 ;;
  esac
done
