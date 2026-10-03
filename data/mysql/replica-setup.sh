#!/bin/sh
# MySQL GTID 복제 설정(소스 → 레플리카). k8s 의 MySQL 파드에 kubectl exec 로 들어가 돌린다. 여러 번 돌려도 된다. 비밀번호는 출력하지 않는다.
#
#   sh data/mysql/replica-setup.sh <대상>            (NS=modu 기본, 컨텍스트는 현재 kubectl 컨텍스트)
#     member | chat | push | profile | commerce | messenger(앞의 넷) | all
#
#   1) 소스에 복제 계정(repl)
#   2) 레플리카가 아직 복제 중이 아니면: 소스의 DB 를 GTID 위치와 함께 덤프해 레플리카에 적재
#      (kubectl exec 소스 mysqldump | kubectl exec -i 레플리카 mysql — 덤프가 Mac 을 거쳐 간다)
#   3) GTID 자동 위치로 복제 시작, read_only·super_read_only 를 SET PERSIST
#      (시작 옵션에 두면 mysql 이미지 첫 초기화가 root 비밀번호를 못 만든다)
#   4) 소스에 앱 읽기 계정(SELECT) — 복제로 레플리카에도 생긴다
#
# 파드: 소스 mysql-<instance>-0, 레플리카 mysql-<instance>-replica-0. 복제 주소(SOURCE_HOST)는 Service 이름 mysql-<instance>.
# 비밀번호: repl·읽기 계정 비밀번호는 Secret infra 에서 읽는다(kubectl get secret infra … | base64 -d).
#   root 는 파드 자신의 env MYSQL_ROOT_PASSWORD(같은 Secret 에서 온 값. 커머스 파드는 COMMERCE_DB_PASSWORD 가 들어 있다)를 파드 안에서
#   MYSQL_PWD 로 쓴다 — kubectl exec 에는 -e 가 없고, 명령줄 인자로 넘기면 파드의 ps 에 보이기 때문.
set -eu
NS=${NS:-modu}

secret_val() { kubectl -n "$NS" get secret infra -o jsonpath="{.data.$1}" | base64 -d; }
# mysql_in POD [mysql 옵션…] — 파드 안에서 root 로 mysql 클라이언트. stdin(SQL)을 그대로 넘긴다.
mysql_in() { _pod=$1; shift; kubectl -n "$NS" exec -i "$_pod" -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot "$@"' sh "$@"; }

setup() {
  INST=$1; REPL_PW=$2; RO_USER=$3; RO_PW=$4; DUMP_DBS=$5; GRANT_DBS=$6
  SRC_HOST="mysql-$INST"; SRC="mysql-$INST-0"; REP="mysql-$INST-replica-0"
  src() { mysql_in "$SRC" "$@"; }
  rep() { mysql_in "$REP" "$@"; }

  echo "== $SRC → $REP"
  echo "[1/4] 소스에 복제 계정"
  src <<SQL
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH caching_sha2_password BY '${REPL_PW}';
ALTER USER 'repl'@'%' IDENTIFIED WITH caching_sha2_password BY '${REPL_PW}';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
SQL

  running=$(rep -N -e "SELECT COUNT(*) FROM performance_schema.replication_connection_status WHERE SERVICE_STATE='ON';" </dev/null 2>/dev/null || echo 0)
  if [ "$running" = "1" ]; then
    echo "[2/4] 레플리카가 이미 복제 중 — 초기 적재 건너뜀"
  else
    echo "[2/4] 초기 적재(소스 덤프 → 레플리카): $DUMP_DBS"
    rep -e "STOP REPLICA; RESET REPLICA ALL;" </dev/null 2>/dev/null || true
    rep -e "SET PERSIST super_read_only=OFF; SET PERSIST read_only=OFF; RESET MASTER;" </dev/null
    for db in $DUMP_DBS; do rep -e "DROP DATABASE IF EXISTS \`$db\`;" </dev/null; done
    # shellcheck disable=SC2086
    kubectl -n "$NS" exec "$SRC" -- sh -c \
      'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot --single-transaction --set-gtid-purged=ON --routines --triggers --events --databases "$@" 2>/dev/null' \
      sh $DUMP_DBS \
      | rep
    echo "[3/4] 복제 시작"
    rep <<SQL
CHANGE REPLICATION SOURCE TO SOURCE_HOST='${SRC_HOST}', SOURCE_PORT=3306, SOURCE_USER='repl',
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
  rep -e "SHOW REPLICA STATUS\G" </dev/null | grep -E "Replica_IO_Running:|Replica_SQL_Running:|Seconds_Behind_Source:|Last_(IO_|SQL_)?Error:" || true
}

messenger() {
  # $1 = member|chat|push|profile, $2 = 덤프할 DB, $3 = 읽기 권한을 줄 DB
  setup "$1" "$(secret_val MESSENGER_REPL_PASSWORD)" modu_ro "$(secret_val MESSENGER_RO_PASSWORD)" "$2" "$3"
}

target() {
  case "$1" in
    # mysql-member 에는 회원(modu-chat)·포인트(modu-point)·스케줄(modu-schedule) 스키마가 함께 있다.
    # 덤프 뒤에 소스에서 새로 만든 스키마는 복제로 따라온다.
    member)   dbs=$(mysql_in mysql-member-0 -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'modu-%'" </dev/null | tr '\n' ' ')
              messenger member "$dbs" "modu-chat modu-point modu-schedule" ;;
    chat|push|profile) messenger "$1" "modu-chat" "modu-chat" ;;
    commerce) setup commerce "$(secret_val COMMERCE_REPL_PASSWORD)" commerce_ro "$(secret_val COMMERCE_RO_PASSWORD)" commerce commerce ;;
    messenger) for t in member chat push profile; do target "$t"; done ;;
    all)       for t in member chat push profile commerce; do target "$t"; done ;;
    *) echo "사용: sh data/mysql/replica-setup.sh member|chat|push|profile|commerce|messenger|all" >&2; exit 2 ;;
  esac
}

target "${1:-}"
