#!/bin/sh
# Temporal 서버가 쓰는 DB 두 개(temporal, temporal_visibility)와 계정(temporal)을 mysql-platform 소스에 만든다(2026-11-14). 복제로 레플리카에도 생긴다.
# 여러 번 돌려도 된다. 비밀번호는 출력하지 않는다.
#
#   sh data/mysql/temporal-db-setup.sh            (NS=modu 기본)
#
# **표는 여기서 만들지 않는다** — Temporal 도구(temporal-sql-tool)가 만들고 버전을 올린다(k8s/base/data/temporal.yaml 의 initContainer `schema`).
# 그래서 이 두 스키마는 schema/*.sql 기준선·gh-ost 절차의 대상이 아니다(DBA.md). DBA 가 하는 일은 DB·계정까지.
# 순서: apply-baseline.sh platform → 이 스크립트 → replica-setup.sh platform (레플리카 덤프 목록에 두 스키마가 들어 있다).
# 비밀번호는 Secret infra 의 TEMPORAL_DB_PASSWORD, root 는 파드 env MYSQL_ROOT_PASSWORD(파드 안에서만 쓴다).
set -eu
NS=${NS:-modu}

PW=$(kubectl -n "$NS" get secret infra -o jsonpath='{.data.TEMPORAL_DB_PASSWORD}' | base64 -d)
[ -n "$PW" ] || { echo "Secret infra 에 TEMPORAL_DB_PASSWORD 가 없다(k8s/infra.env → create-infra-secret.sh)" >&2; exit 1; }

cat <<SQL | kubectl -n "$NS" exec -i mysql-platform-0 -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot'
CREATE DATABASE IF NOT EXISTS \`temporal\`            DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS \`temporal_visibility\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS 'temporal'@'%' IDENTIFIED WITH caching_sha2_password BY '${PW}';
ALTER USER 'temporal'@'%' IDENTIFIED WITH caching_sha2_password BY '${PW}';
GRANT ALL ON \`temporal\`.* TO 'temporal'@'%';
GRANT ALL ON \`temporal_visibility\`.* TO 'temporal'@'%';
SQL
echo "== mysql-platform-0: temporal@% (temporal, temporal_visibility)"
