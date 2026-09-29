#!/bin/sh
# MySQL GTID 복제 설정(소스 → 레플리카). 여러 번 돌려도 된다. 비밀번호는 출력하지 않는다.
#
#   sh mysql/replica-setup.sh <대상>
#     member | chat | push | profile | commerce | messenger(앞의 넷) | all
#
#   1) 소스에 복제 계정(repl)
#   2) 레플리카가 아직 복제 중이 아니면: 소스의 DB 를 GTID 위치와 함께 덤프해 레플리카에 적재
#   3) GTID 자동 위치로 복제 시작, read_only·super_read_only 를 SET PERSIST
#      (시작 옵션에 두면 mysql 이미지 첫 초기화가 root 비밀번호를 못 만든다)
#   4) 소스에 앱 읽기 계정(SELECT) — 복제로 레플리카에도 생긴다
set -eu
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

setup() {
  SRC=$1; REP=$2; ROOT_PW=$3; REPL_PW=$4; RO_USER=$5; RO_PW=$6; DUMP_DBS=$7; GRANT_DBS=$8
  src() { docker exec -i -e MYSQL_PWD="$ROOT_PW" "$SRC" mysql -uroot "$@"; }
  rep() { docker exec -i -e MYSQL_PWD="$ROOT_PW" "$REP" mysql -uroot "$@"; }

  echo "== $SRC → $REP"
  echo "[1/4] 소스에 복제 계정"
  src <<SQL
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH caching_sha2_password BY '${REPL_PW}';
ALTER USER 'repl'@'%' IDENTIFIED WITH caching_sha2_password BY '${REPL_PW}';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
SQL

  running=$(rep -N -e "SELECT COUNT(*) FROM performance_schema.replication_connection_status WHERE SERVICE_STATE='ON';" 2>/dev/null || echo 0)
  if [ "$running" = "1" ]; then
    echo "[2/4] 레플리카가 이미 복제 중 — 초기 적재 건너뜀"
  else
    echo "[2/4] 초기 적재(소스 덤프 → 레플리카): $DUMP_DBS"
    rep -e "STOP REPLICA; RESET REPLICA ALL;" 2>/dev/null || true
    rep -e "SET PERSIST super_read_only=OFF; SET PERSIST read_only=OFF; RESET MASTER;"
    for db in $DUMP_DBS; do rep -e "DROP DATABASE IF EXISTS \`$db\`;"; done
    # shellcheck disable=SC2086
    docker exec -e MYSQL_PWD="$ROOT_PW" "$SRC" \
      mysqldump -uroot --single-transaction --set-gtid-purged=ON --routines --triggers --events --databases $DUMP_DBS 2>/dev/null \
      | rep
    echo "[3/4] 복제 시작"
    rep <<SQL
CHANGE REPLICATION SOURCE TO SOURCE_HOST='${SRC}', SOURCE_PORT=3306, SOURCE_USER='repl',
  SOURCE_PASSWORD='${REPL_PW}', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
SET PERSIST read_only=ON;
SET PERSIST super_read_only=ON;
SQL
  fi

  echo "[4/4] 앱 읽기 계정 ${RO_USER}"
  {
    echo "CREATE USER IF NOT EXISTS '${RO_USER}'@'%' IDENTIFIED WITH caching_sha2_password BY '${RO_PW}';"
    echo "ALTER USER '${RO_USER}'@'%' IDENTIFIED WITH caching_sha2_password BY '${RO_PW}';"
    for db in $GRANT_DBS; do echo "GRANT SELECT ON \`$db\`.* TO '${RO_USER}'@'%';"; done
  } | src

  sleep 2
  rep -e "SHOW REPLICA STATUS\G" | grep -E "Replica_IO_Running:|Replica_SQL_Running:|Seconds_Behind_Source:|Last_(IO_|SQL_)?Error:" || true
}

messenger() {
  : "${MYSQL_ROOT_PASSWORD:?}" "${MESSENGER_REPL_PASSWORD:?}" "${MESSENGER_RO_PASSWORD:?}"
  # $1 = member|chat|push|profile, $2 = 덤프할 DB, $3 = 읽기 권한을 줄 DB
  setup "mysql-$1" "mysql-$1-replica" "$MYSQL_ROOT_PASSWORD" "$MESSENGER_REPL_PASSWORD" modu_ro "$MESSENGER_RO_PASSWORD" "$2" "$3"
}

target() {
  case "$1" in
    # mysql-member 에는 회원(modu-chat)·포인트(modu-point)·스케줄(modu-schedule) 스키마가 함께 있다.
    # 덤프 뒤에 소스에서 새로 만든 스키마는 복제로 따라온다.
    member)   dbs=$(docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql-member mysql -uroot -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'modu-%'" | tr '\n' ' ')
              messenger member "$dbs" "modu-chat modu-point modu-schedule" ;;
    chat|push|profile) messenger "$1" "modu-chat" "modu-chat" ;;
    commerce) : "${COMMERCE_DB_PASSWORD:?}" "${COMMERCE_REPL_PASSWORD:?}" "${COMMERCE_RO_PASSWORD:?}"
              setup mysql-commerce mysql-commerce-replica "$COMMERCE_DB_PASSWORD" "$COMMERCE_REPL_PASSWORD" commerce_ro "$COMMERCE_RO_PASSWORD" commerce commerce ;;
    messenger) for t in member chat push profile; do target "$t"; done ;;
    all)       for t in member chat push profile commerce; do target "$t"; done ;;
    *) echo "사용: sh mysql/replica-setup.sh member|chat|push|profile|commerce|messenger|all" >&2; exit 2 ;;
  esac
}

target "${1:-}"
