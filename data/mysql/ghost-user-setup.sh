#!/bin/sh
# gh-ost 가 쓰는 DB 계정(ghost)을 소스에 만든다. 복제로 레플리카에도 생긴다. 여러 번 돌려도 된다. 비밀번호는 출력하지 않는다.
#
#   sh data/mysql/ghost-user-setup.sh            # member chat push profile commerce 전부   (NS=modu 기본)
#   sh data/mysql/ghost-user-setup.sh commerce   # 하나만
#
# 소스 파드 mysql-<instance>-0 에 kubectl exec. 비밀번호는 Secret infra 의 GHOST_PASSWORD, root 는 파드 env MYSQL_ROOT_PASSWORD(파드 안에서만 쓴다).
# 권한(gh-ost 문서 그대로): 대상 스키마에 ALTER CREATE DELETE DROP INDEX INSERT LOCK TABLES SELECT TRIGGER UPDATE,
# 전역으로 REPLICATION CLIENT·REPLICATION SLAVE(레플리카 바이너리 로그를 읽는다), performance_schema SELECT + setup_instruments UPDATE
# (cut-over 의 메타데이터 잠금 감시). SUPER 는 주지 않는다 — ghost.sh 가 --assume-rbr 로 돈다.
set -eu
NS=${NS:-modu}

GHOST_PASSWORD=$(kubectl -n "$NS" get secret infra -o jsonpath='{.data.GHOST_PASSWORD}' | base64 -d)
[ -n "$GHOST_PASSWORD" ] || { echo "Secret infra 에 GHOST_PASSWORD 가 없다(k8s/infra.env → create-infra-secret.sh)" >&2; exit 1; }

# 스키마마다 정확한 이름으로 준다. gh-ost 는 SHOW GRANTS 에서 대상 스키마 이름을 그대로 찾기 때문에
# 와일드카드(`modu-%`.*)로 주면 "user has insufficient privileges" 로 멈춘다.
grant() { # $1 instance  $2.. 스키마 이름들
  instance=$1; shift
  schemas=$*
  { echo "CREATE USER IF NOT EXISTS 'ghost'@'%' IDENTIFIED WITH caching_sha2_password BY '${GHOST_PASSWORD}';"
    echo "ALTER USER 'ghost'@'%' IDENTIFIED WITH caching_sha2_password BY '${GHOST_PASSWORD}';"
    for s in $schemas; do
      echo "GRANT ALTER, CREATE, DELETE, DROP, INDEX, INSERT, LOCK TABLES, SELECT, TRIGGER, UPDATE ON \`$s\`.* TO 'ghost'@'%';"
    done
    echo "GRANT REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'ghost'@'%';"
    # cut-over 때 메타데이터 잠금(metadata_locks·threads)을 보고, mdl instrument 를 확인·활성화한다(gh-ost 1.1.9+)
    echo "GRANT SELECT ON performance_schema.* TO 'ghost'@'%';"
    echo "GRANT UPDATE ON performance_schema.setup_instruments TO 'ghost'@'%';"
  } | kubectl -n "$NS" exec -i "mysql-$instance-0" -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot'
  echo "== mysql-$instance-0: ghost@% ($schemas)"
}

for t in ${*:-member chat push profile commerce platform}; do
  case "$t" in
    member)   grant member 'modu-chat' 'modu-point' 'modu-schedule' ;;
    chat)     grant chat 'modu-chat' ;;
    push)     grant push 'modu-chat' ;;
    profile)  grant profile 'modu-chat' ;;
    commerce) grant commerce commerce ;;
    platform) grant platform 'modu-platform' ;;
    *) echo "사용: sh data/mysql/ghost-user-setup.sh [member|chat|push|profile|commerce|platform ...]" >&2; exit 2 ;;
  esac
done
