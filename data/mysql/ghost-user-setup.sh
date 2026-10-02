#!/bin/sh
# gh-ost 가 쓰는 DB 계정(ghost)을 소스에 만든다. 복제로 레플리카에도 생긴다. 여러 번 돌려도 된다. 비밀번호는 출력하지 않는다.
#
#   sh mysql/ghost-user-setup.sh            # member chat push profile commerce 전부
#   sh mysql/ghost-user-setup.sh commerce   # 하나만
#
# 권한(gh-ost 문서 그대로): 대상 스키마에 ALTER CREATE DELETE DROP INDEX INSERT LOCK TABLES SELECT TRIGGER UPDATE,
# 전역으로 REPLICATION CLIENT·REPLICATION SLAVE(레플리카 바이너리 로그를 읽는다), performance_schema SELECT + setup_instruments UPDATE
# (cut-over 의 메타데이터 잠금 감시). SUPER 는 주지 않는다 — ghost.sh 가 --assume-rbr 로 돈다.
set -eu
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${GHOST_PASSWORD:?data/.env 에 GHOST_PASSWORD 가 필요하다}"

grant() { # $1 컨테이너  $2 root 비밀번호  $3 스키마 패턴
  docker exec -i -e MYSQL_PWD="$2" "$1" mysql -uroot <<SQL
CREATE USER IF NOT EXISTS 'ghost'@'%' IDENTIFIED WITH caching_sha2_password BY '${GHOST_PASSWORD}';
ALTER USER 'ghost'@'%' IDENTIFIED WITH caching_sha2_password BY '${GHOST_PASSWORD}';
GRANT ALTER, CREATE, DELETE, DROP, INDEX, INSERT, LOCK TABLES, SELECT, TRIGGER, UPDATE ON \`$3\`.* TO 'ghost'@'%';
GRANT REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'ghost'@'%';
-- cut-over 때 메타데이터 잠금(metadata_locks·threads)을 보고, mdl instrument 를 확인·활성화한다(gh-ost 1.1.9+)
GRANT SELECT ON performance_schema.* TO 'ghost'@'%';
GRANT UPDATE ON performance_schema.setup_instruments TO 'ghost'@'%';
SQL
  echo "== $1: ghost@% ($3)"
}

for t in ${*:-member chat push profile commerce}; do
  case "$t" in
    member|chat|push|profile) grant "mysql-$t" "${MYSQL_ROOT_PASSWORD:?}" 'modu-%' ;;
    commerce)                 grant mysql-commerce "${COMMERCE_DB_PASSWORD:?}" commerce ;;
    *) echo "사용: sh mysql/ghost-user-setup.sh [member|chat|push|profile|commerce ...]" >&2; exit 2 ;;
  esac
done
