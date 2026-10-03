#!/bin/sh
# gh-ost 로 테이블을 온라인으로 바꾼다. k8s(네임스페이스 modu)의 일회용 파드(kubectl run --rm)로 돈다. 절차와 원칙은 DBA.md.
#
#   sh data/mysql/ghost.sh <instance> <schema> <table> "<ALTER 본문>" [--execute] [--auto-cutover]     (NS=modu 기본)
#     instance: member | chat | push | profile | commerce   (레플리카 Service mysql-<instance>-replica 에 붙는다)
#     예) sh data/mysql/ghost.sh commerce commerce orders "ADD COLUMN gift_message VARCHAR(200) NULL"
#         sh data/mysql/ghost.sh commerce commerce orders "ADD COLUMN gift_message VARCHAR(200) NULL" --execute
#
# --execute 없이 돌리면 검사만 한다(테이블·권한·바이너리 로그·행 수 추정). 실제 적용은 --execute.
# 동작: 레플리카(mysql-<instance>-replica)의 바이너리 로그를 읽어 변경을 따라가고, 소스에서 그림자 테이블(_<table>_gho)을
#       채운 뒤 이름을 바꿔치기(cut-over)한다. 원래 테이블은 _<table>_<timestamp>_del 로 남으니 확인 뒤 직접 DROP 한다.
# 파드: gh-ost-<table>-<ts>. 이미지 modu-gh-ost:1.1.11 은 노드(containerd)에 있어야 한다(imagePullPolicy Never, 레지스트리 없음)
#       — 없으면 먼저 sh data/mysql/gh-ost/build-and-import.sh. 파드는 끝나면 지워진다(--rm). 터미널(Ctrl-C)을 끊으면 kubectl 이
#       파드를 지우므로 gh-ost 도 죽는다 — 길게 돌면 GHOST_TTY=-i 로 돌리고 로그는 다른 터미널에서 kubectl -n modu logs -f <pod>.
# cut-over 는 기본으로 멈춰서 기다린다: gh-ost 가 파드 안 /run/ghost/<table>.postpone 을 만들어 두고, 복사가 끝나면
#   "State: postponing cut-over" 로 대기한다. 로그에서 Copy 100%·Lag 를 확인한 뒤 그 파일을 지우면 교체한다.
#   작은 테이블이라 바로 교체해도 되면 --auto-cutover 를 붙인다.
# 실행 중 조작(다른 터미널에서. 파드 이름은 시작할 때 찍는다):
#   kubectl -n modu exec <pod> -- rm /run/ghost/<table>.postpone     cut-over 진행
#   kubectl -n modu exec <pod> -- touch /run/ghost/<table>.throttle  잠시 멈춘다(파일을 지우면 재개)
#   kubectl -n modu exec <pod> -- touch /run/ghost/<table>.panic     즉시 중단(그림자 테이블은 남는다. 다음 실행이 --initially-drop-ghost-table 로 지운다)
#   kubectl -n modu exec <pod> -- sh -c 'echo status | socat - /run/ghost/<table>.sock'   진행률(이미지에 socat 이 없으면 로그만 봐도 충분)
# 비밀번호: ghost 계정 비밀번호는 Secret infra 의 GHOST_PASSWORD 를 읽어 gh-ost 의 --password 인자로 준다(화면엔 안 찍는다. 파드 spec 에는 들어가고
#   파드는 끝나면 지워진다). GHOST_TTY=-i 로 두면 터미널 없이(스크립트·CI) 돈다.
set -eu
NS=${NS:-modu}

[ $# -ge 4 ] || { echo "사용: sh data/mysql/ghost.sh <instance> <schema> <table> \"<ALTER 본문>\" [--execute] [--auto-cutover]" >&2; exit 2; }
INSTANCE=$1; SCHEMA=$2; TABLE=$3; ALTER=$4
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
# 파드 이름: 소문자·숫자·- 만(테이블 이름의 _ 는 - 로)
POD="gh-ost-$(printf '%s' "$TABLE" | tr '_A-Z' '-a-z' | tr -c 'a-z0-9-' '-')-$(date +%Y%m%d%H%M%S)"

GHOST_PASSWORD=$(kubectl -n "$NS" get secret infra -o jsonpath='{.data.GHOST_PASSWORD}' | base64 -d)
[ -n "$GHOST_PASSWORD" ] || { echo "Secret infra 에 GHOST_PASSWORD 가 없다(k8s/infra.env → create-infra-secret.sh)" >&2; exit 1; }

# 이미지가 노드에 있는지(Docker Desktop: docker 로 노드 컨테이너의 containerd 를 본다). docker 가 없으면 건너뛴다 — 없으면 파드가 ErrImageNeverPull 로 멈춘다.
if command -v docker >/dev/null 2>&1 && images=$(docker exec desktop-control-plane ctr -n k8s.io images ls -q 2>/dev/null); then
  echo "$images" | grep -qx "docker.io/library/$IMAGE" \
    || { echo "노드에 $IMAGE 가 없다 — 먼저: sh data/mysql/gh-ost/build-and-import.sh" >&2; exit 1; }
fi

echo "== gh-ost ${INSTANCE}/${SCHEMA}.${TABLE}  ${EXECUTE:-(검사만)}   pod: $POD"
echo "   ALTER TABLE \`${TABLE}\` ${ALTER}"
# shellcheck disable=SC2086
exec kubectl -n "$NS" run "$POD" --rm ${GHOST_TTY:--it} --restart=Never --image="$IMAGE" --image-pull-policy=Never --quiet -- \
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
