#!/bin/sh
# 새 클러스터에서 스키마 기준선(schema/<instance>.<schema>.sql)을 소스 DB(파드 mysql-<instance>-0)에 손으로 적용한다(2026-10-08 결정:
# 앱은 ddl-auto validate, init 스크립트도 없다 — 스키마는 DBA 가 만든다). 데이터는 넣지 않는다(데이터는 덤프 복원 — k8s/README "Colima").
# 이미 표가 있는 스키마에는 손대지 않고 멈춘다(운영 DB 를 덮어쓰지 않게). 적용 뒤 레플리카는 replica-setup.sh 가 덤프로 맞춘다.
#
#   sh data/mysql/apply-baseline.sh platform            # 하나만 (member | chat | push | profile | commerce | platform)
#   sh data/mysql/apply-baseline.sh platform member     # 여러 개
#   POD=mysql-test-0 sh data/mysql/apply-baseline.sh platform   # 다른 파드로(시험용)
#
# root 비밀번호는 파드 env MYSQL_ROOT_PASSWORD 를 파드 안에서만 쓴다(화면에 안 찍는다).
set -eu
NS=${NS:-modu}
cd "$(dirname "$0")"

sql() { # $1 pod, stdin = SQL
  kubectl -n "$NS" exec -i "$1" -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot'
}

apply() { # $1 instance  $2 schema
  pod=${POD:-mysql-$1-0}
  file="schema/$1.$2.sql"
  [ -f "$file" ] || { echo "기준선이 없다: $file" >&2; exit 1; }
  have=$(echo "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$2';" | sql "$pod" | tail -1)
  if [ "$have" != "0" ]; then
    echo "== $pod / \`$2\`: 이미 표 ${have}개 — 건너뜀(운영 DB 는 gh-ost 로 바꾼다, DBA.md)"; return 0
  fi
  { echo "CREATE DATABASE IF NOT EXISTS \`$2\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"; echo "USE \`$2\`;"; cat "$file"; } | sql "$pod"
  n=$(echo "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$2';" | sql "$pod" | tail -1)
  echo "== $pod / \`$2\`: $file 적용 — 표 ${n}개 (기준선 $(grep -c '^CREATE TABLE' "$file")개)"
}

[ $# -gt 0 ] || { echo "사용: sh data/mysql/apply-baseline.sh member|chat|push|profile|commerce|platform ..." >&2; exit 2; }
for t in "$@"; do
  case "$t" in
    member)   for s in modu-chat modu-point modu-schedule; do apply member "$s"; done ;;
    chat|push|profile) apply "$t" modu-chat ;;
    commerce) apply commerce commerce ;;
    platform) apply platform modu-platform ;;
    *) echo "사용: sh data/mysql/apply-baseline.sh member|chat|push|profile|commerce|platform ..." >&2; exit 2 ;;
  esac
done
