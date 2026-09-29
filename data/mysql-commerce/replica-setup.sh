#!/bin/sh
# 커머스 MySQL 복제 설정(소스 mysql-commerce → 레플리카 mysql-commerce-replica). 여러 번 돌려도 된다.
#   1) 소스에 복제 계정(repl)
#   2) 레플리카가 아직 복제 중이 아니면: 소스의 commerce DB 를 GTID 위치와 함께 덤프해 레플리카에 적재
#   3) GTID 자동 위치로 복제 시작
#   4) 소스에 앱 읽기 계정(commerce_ro, SELECT) — 복제로 레플리카에도 생긴다
# 사용: data/ 에서 `sh mysql-commerce/replica-setup.sh` (data/.env 를 읽는다). 비밀번호는 출력하지 않는다.
set -eu
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${COMMERCE_DB_PASSWORD:?}" "${COMMERCE_REPL_PASSWORD:?}" "${COMMERCE_RO_PASSWORD:?}"

src() { docker exec -i -e MYSQL_PWD="$COMMERCE_DB_PASSWORD" mysql-commerce mysql -uroot "$@"; }
rep() { docker exec -i -e MYSQL_PWD="$COMMERCE_DB_PASSWORD" mysql-commerce-replica mysql -uroot "$@"; }

echo "[1/4] 소스에 복제 계정"
src -e "CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH caching_sha2_password BY '${COMMERCE_REPL_PASSWORD}';
        ALTER USER 'repl'@'%' IDENTIFIED WITH caching_sha2_password BY '${COMMERCE_REPL_PASSWORD}';
        GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';"

running=$(rep -N -e "SELECT COUNT(*) FROM performance_schema.replication_connection_status WHERE SERVICE_STATE='ON';" 2>/dev/null || echo 0)
if [ "$running" = "1" ]; then
  echo "[2/4] 레플리카가 이미 복제 중 — 초기 적재 건너뜀"
else
  echo "[2/4] 초기 적재(소스 덤프 → 레플리카)"
  rep -e "STOP REPLICA; RESET REPLICA ALL;" 2>/dev/null || true
  rep -e "SET PERSIST super_read_only=OFF; SET PERSIST read_only=OFF; RESET MASTER; DROP DATABASE IF EXISTS commerce;"
  docker exec -e MYSQL_PWD="$COMMERCE_DB_PASSWORD" mysql-commerce \
    mysqldump -uroot --single-transaction --set-gtid-purged=ON --routines --triggers --events --databases commerce \
    | rep
  echo "[3/4] 복제 시작"
  rep -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='mysql-commerce', SOURCE_PORT=3306, SOURCE_USER='repl',
            SOURCE_PASSWORD='${COMMERCE_REPL_PASSWORD}', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1;
          START REPLICA;
          SET PERSIST read_only=ON; SET PERSIST super_read_only=ON;"
fi

echo "[4/4] 앱 읽기 계정(소스에 만들고 복제로 전파)"
src -e "CREATE USER IF NOT EXISTS 'commerce_ro'@'%' IDENTIFIED WITH caching_sha2_password BY '${COMMERCE_RO_PASSWORD}';
        ALTER USER 'commerce_ro'@'%' IDENTIFIED WITH caching_sha2_password BY '${COMMERCE_RO_PASSWORD}';
        GRANT SELECT ON commerce.* TO 'commerce_ro'@'%';"

sleep 2
rep -e "SHOW REPLICA STATUS\G" | grep -E "Replica_IO_Running:|Replica_SQL_Running:|Seconds_Behind_Source:|Last_(IO_|SQL_)?Error:" || true
