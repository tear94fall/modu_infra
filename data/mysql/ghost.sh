#!/bin/sh
# gh-ost 로 테이블을 온라인으로 바꾼다. 절차와 원칙은 DBA.md.
#
#   sh mysql/ghost.sh <instance> <schema> <table> "<ALTER 본문>" [--execute]
#     instance: member | chat | push | profile | commerce   (소스 컨테이너 mysql-<instance>, 레플리카 mysql-<instance>-replica)
#     예) sh mysql/ghost.sh commerce commerce orders "ADD COLUMN gift_message VARCHAR(200) NULL"
#         sh mysql/ghost.sh commerce commerce orders "ADD COLUMN gift_message VARCHAR(200) NULL" --execute
#
# --execute 없이 돌리면 검사만 한다(테이블·권한·바이너리 로그·행 수 추정). 실제 적용은 --execute.
# 동작: 레플리카(mysql-<instance>-replica)의 바이너리 로그를 읽어 변경을 따라가고, 소스에서 그림자 테이블(_<table>_gho)을
#       채운 뒤 이름을 바꿔치기(cut-over)한다. 원래 테이블은 _<table>_<timestamp>_del 로 남으니 확인 뒤 직접 DROP 한다.
# cut-over 는 기본으로 멈춰서 기다린다: gh-ost 가 mysql/ghost-run/<table>.postpone 을 만들어 두고, 복사가 끝나면
#   "State: postponing cut-over" 로 대기한다. 로그에서 Copy 100%·Lag 를 확인한 뒤 그 파일을 지우면 교체한다.
#   작은 테이블이라 바로 교체해도 되면 --auto-cutover 를 붙인다.
# 실행 중 조작(mysql/ghost-run/ 디렉터리):
#   rm    ghost-run/<table>.postpone   cut-over 진행
#   touch ghost-run/<table>.throttle   잠시 멈춘다(파일을 지우면 재개)
#   touch ghost-run/<table>.panic      즉시 중단(그림자 테이블은 남는다. 다음 실행이 --initially-drop-ghost-table 로 지운다)
#   echo status | socat - ghost-run/<table>.sock   진행률 (socat 이 없으면 로그만 봐도 충분)
set -eu
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${GHOST_PASSWORD:?data/.env 에 GHOST_PASSWORD 가 필요하다}"

INSTANCE=${1:?instance}; SCHEMA=${2:?schema}; TABLE=${3:?table}; ALTER=${4:?alter}
shift 4
EXECUTE=""; POSTPONE="--postpone-cut-over-flag-file=/run/ghost/${TABLE}.postpone"
for a in "$@"; do
  case "$a" in
    --execute) EXECUTE="--execute" ;;
    --auto-cutover) POSTPONE="" ;;
    *) echo "모르는 옵션: $a (--execute | --auto-cutover)" >&2; exit 2 ;;
  esac
done

case "$INSTANCE" in
  member|chat|push|profile|commerce) ;;
  *) echo "instance 는 member|chat|push|profile|commerce" >&2; exit 2 ;;
esac
REPLICA="mysql-${INSTANCE}-replica"
IMAGE=modu-gh-ost:1.1.11
RUN_DIR="$PWD/mysql/ghost-run"
mkdir -p "$RUN_DIR"

docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build -q -t "$IMAGE" mysql/gh-ost >/dev/null

echo "== gh-ost ${INSTANCE}/${SCHEMA}.${TABLE}  ${EXECUTE:-(검사만)}"
echo "   ALTER TABLE \`${TABLE}\` ${ALTER}"
# shellcheck disable=SC2086
# GHOST_TTY=-i 로 두면 터미널 없이(스크립트·CI) 돈다.
exec docker run --rm ${GHOST_TTY:--it} --network modu-infra \
  -v "$RUN_DIR:/run/ghost" \
  -e GHOST_PASSWORD \
  "$IMAGE" \
  --host="$REPLICA" --port=3306 --user=ghost --password="$GHOST_PASSWORD" \
  --database="$SCHEMA" --table="$TABLE" --alter="$ALTER" \
  --assume-rbr \
  --throttle-control-replicas="$REPLICA" --max-lag-millis=1500 \
  --max-load=Threads_running=25 --critical-load=Threads_running=60 \
  --chunk-size=1000 --default-retries=120 \
  --cut-over=default --timestamp-old-table \
  --initially-drop-ghost-table --initially-drop-socket-file \
  $POSTPONE \
  --throttle-flag-file="/run/ghost/${TABLE}.throttle" \
  --panic-flag-file="/run/ghost/${TABLE}.panic" \
  --serve-socket-file="/run/ghost/${TABLE}.sock" \
  --verbose $EXECUTE
