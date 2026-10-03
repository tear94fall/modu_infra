#!/usr/bin/env bash
# 인프라(base/data, base/observability)가 읽는 Secret 3개를 compose 의 .env·키 파일에서 만든다(있으면 덮어쓴다 — apply).
#   infra            data/.env 전부(MINIO_DATA_DIR 제외) + monitoring/.env 전부 + pinpoint-docker/.env 의 비밀 8개(PINPOINT_ 접두사)
#   mongo-keyfile    data/mongodb/mongodb.key        (mongo 의 replica set 내부 인증 키)
#   mysqld-exporter  monitoring/mysql/.my.cnf         ([client] 메신저 root, [client.commerce] 커머스 root)
# 키 이름은 .env 의 변수 이름 그대로다(MYSQL_ROOT_PASSWORD, COMMERCE_DB_PASSWORD, GRAFANA_PASSWORD …). 키 목록은 infra-secrets.example.env.
# pinpoint-docker/.env 는 MYSQL_ROOT_PASSWORD 처럼 data/.env 와 이름이 겹쳐서 PINPOINT_ 를 붙인다.
#
# .env 는 source 하지 않는다 — pinpoint-docker/.env 처럼 셸에 안전하지 않은 줄(공백·${…}·-D 옵션)이 섞여 있다. KEY=VALUE 줄만 읽고,
# 값 양끝의 따옴표는 compose 처럼 벗기며, 값에 ${ · 공백이 있거나 -D 로 시작하거나 비어 있는 줄은 건너뛴다(경고). 필요한 키가 빠지면 실패한다.
# 값은 화면에 찍지 않는다.
#
# 사용: k8s/create-infra-secret.sh            (MODU_INFRA=~/workspace/modu_infra 기본, 컨텍스트는 현재 kubectl 컨텍스트)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${MODU_INFRA:-$(cd "$HERE/.." && pwd)}"
NS=modu
DATA_ENV="$ROOT/data/.env"
MON_ENV="$ROOT/monitoring/.env"
PP_ENV="$ROOT/pinpoint-docker/.env"
MONGO_KEY="$ROOT/data/mongodb/mongodb.key"
MY_CNF="$ROOT/monitoring/mysql/.my.cnf"

for f in "$DATA_ENV" "$MON_ENV" "$PP_ENV" "$MONGO_KEY" "$MY_CNF"; do
  [ -r "$f" ] || { echo "읽을 수 없다: $f" >&2; exit 1; }
done

ARGS=()   # --from-literal=KEY=VALUE …
KEYS=" "  # 이미 넣은 키(중복 방지 — 같은 키가 여러 줄이면 compose 처럼 마지막 값)

# value_of FILE KEY → 마지막 KEY= 줄의 값(따옴표 벗김). 없으면 비어 있는 출력 + 1 반환.
value_of() {
  local line val
  line="$(grep -E "^[[:space:]]*$2=" "$1" | tail -n 1)" || return 1
  val="${line#*=}"
  val="${val%$'\r'}"
  case "$val" in
    \"*\") val="${val#\"}"; val="${val%\"}" ;;
    \'*\') val="${val#\'}"; val="${val%\'}" ;;
  esac
  printf '%s' "$val"
}

# add SECRET_KEY FILE ENV_KEY
add() {
  local key="$1" file="$2" src="$3" val
  case "$KEYS" in *" $key "*) return 0 ;; esac
  val="$(value_of "$file" "$src")" || { echo "  skip $key: $file 에 $src 가 없다" >&2; return 0; }
  case "$val" in
    "")              echo "  skip $key: 빈 값" >&2; return 0 ;;
    *'${'*)          echo "  skip $key: 값에 \${ 가 있다(셸 치환)" >&2; return 0 ;;
    *[[:space:]]*)   echo "  skip $key: 값에 공백이 있다" >&2; return 0 ;;
    -D*)             echo "  skip $key: 값이 -D 로 시작한다(JVM 옵션 줄)" >&2; return 0 ;;
  esac
  ARGS+=("--from-literal=$key=$val")
  KEYS="$KEYS$key "
}

# 파일의 모든 KEY= 줄(주석·빈 줄 제외)
keys_in() { grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$1" | sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=.*/\1/' | awk '!seen[$0]++'; }

echo "data/.env"
for k in $(keys_in "$DATA_ENV"); do
  [ "$k" = MINIO_DATA_DIR ] && continue   # 호스트 bind mount 경로 — k8s 는 PVC
  add "$k" "$DATA_ENV" "$k"
done
echo "monitoring/.env"
for k in $(keys_in "$MON_ENV"); do add "$k" "$MON_ENV" "$k"; done
echo "pinpoint-docker/.env (PINPOINT_ 접두사)"
for k in MYSQL_ROOT_PASSWORD MYSQL_PASSWORD ADMIN_PASSWORD SPRING_DATASOURCE_HIKARI_PASSWORD SPRING_METADATASOURCE_HIKARI_PASSWORD \
         WEB_SECURITY_AUTH_USER WEB_SECURITY_AUTH_ADMIN WEB_SECURITY_AUTH_JWT_SECRETKEY; do
  add "PINPOINT_$k" "$PP_ENV" "$k"
done

# 매니페스트가 secretKeyRef 로 읽는 키 — 하나라도 없으면 그 파드가 CreateContainerConfigError 로 멈추므로 여기서 실패한다.
REQUIRED="MYSQL_ROOT_PASSWORD MYSQL_USER_PASSWORD COMMERCE_DB_PASSWORD MONGO_ROOT_PASSWORD MINIO_ROOT_PASSWORD
GRAFANA_USER GRAFANA_PASSWORD MONGODB_URI
PINPOINT_MYSQL_ROOT_PASSWORD PINPOINT_MYSQL_PASSWORD PINPOINT_ADMIN_PASSWORD PINPOINT_SPRING_DATASOURCE_HIKARI_PASSWORD
PINPOINT_SPRING_METADATASOURCE_HIKARI_PASSWORD PINPOINT_WEB_SECURITY_AUTH_USER PINPOINT_WEB_SECURITY_AUTH_ADMIN PINPOINT_WEB_SECURITY_AUTH_JWT_SECRETKEY"
missing=""
for k in $REQUIRED; do
  case "$KEYS" in *" $k "*) ;; *) missing="$missing $k" ;; esac
done
[ -z "$missing" ] || { echo "필수 키가 없다:$missing" >&2; exit 1; }

kubectl apply -f "$HERE/base/namespace.yaml" >/dev/null

kubectl -n "$NS" create secret generic infra "${ARGS[@]}" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic mongo-keyfile --from-file=mongodb.key="$MONGO_KEY" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic mysqld-exporter --from-file=.my.cnf="$MY_CNF" --dry-run=client -o yaml | kubectl apply -f -
echo "Secret infra 키:$KEYS"
