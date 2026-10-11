#!/usr/bin/env bash
# 인프라(base/data, base/observability)가 읽는 Secret 3개를 k8s/infra.env + k8s/mongodb.key 에서 만든다(있으면 덮어쓴다 — apply).
#   infra            k8s/infra.env 의 KEY=VALUE 전부(23개. 키 목록·뜻은 infra-secrets.example.env)
#   mongo-keyfile    k8s/mongodb.key                   (mongo 의 replica set 내부 인증 키, 1024B)
#   deploy-service   k8s/deploy-github-app.pem + k8s/argocd-deploy-token  (GitHub App 비밀키·Argo CD 토큰 — 있는 것만 담는다)
#   mysqld-exporter  .my.cnf — infra.env 의 MYSQL_ROOT_PASSWORD([client], 메신저 root)·COMMERCE_DB_PASSWORD([client.commerce], 커머스 root)로 만든다
# 두 파일은 gitignored. 처음이면 infra-secrets.example.env 를 infra.env 로 복사해 값을 채운다(값은 compose 시절 data/.env·monitoring/.env·pinpoint-docker/.env 를 2026-10-04 에 합친 것).
#
# infra.env 는 source 하지 않는다 — KEY=VALUE 줄만 읽고, 값 양끝의 따옴표는 compose 처럼 벗기며, 값에 ${ · 공백이 있거나 -D 로 시작하거나
# 비어 있는 줄은 건너뛴다(경고). 매니페스트·운영 스크립트가 쓰는 키가 빠지면 실패한다. 값은 화면에 찍지 않는다.
#
# 사용: k8s/create-infra-secret.sh            (INFRA_ENV·MONGO_KEY 로 파일 위치를 바꿀 수 있다. 컨텍스트는 현재 kubectl 컨텍스트)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NS=${NS:-modu}
INFRA_ENV="${INFRA_ENV:-$HERE/infra.env}"
MONGO_KEY="${MONGO_KEY:-$HERE/mongodb.key}"
APP_KEY="${APP_KEY:-$HERE/deploy-github-app.pem}"   # deploy-service 의 GitHub App 비밀키(PKCS#8 PEM, gitignored)
ARGO_TOKEN="${ARGO_TOKEN:-$HERE/argocd-deploy-token}" # Argo CD 로컬 계정 deploy 의 API 토큰 한 줄(gitignored)

for f in "$INFRA_ENV" "$MONGO_KEY"; do
  [ -r "$f" ] || { echo "읽을 수 없다: $f  (infra-secrets.example.env 를 보고 만든다)" >&2; exit 1; }
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

# add KEY
add() {
  local key="$1" val
  case "$KEYS" in *" $key "*) return 0 ;; esac
  val="$(value_of "$INFRA_ENV" "$key")" || { echo "  skip $key: 없다" >&2; return 0; }
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

echo "$INFRA_ENV"
for k in $(keys_in "$INFRA_ENV"); do add "$k"; done

# 매니페스트가 secretKeyRef 로 읽는 키(하나라도 없으면 그 파드가 CreateContainerConfigError 로 멈춘다)
# + 운영 스크립트(data/mysql/*.sh)가 읽는 키. 하나라도 없으면 여기서 실패한다.
REQUIRED="MYSQL_ROOT_PASSWORD MYSQL_USER_PASSWORD COMMERCE_DB_PASSWORD PLATFORM_DB_PASSWORD PLATFORM_DB_USER_PASSWORD PLATFORM_REPL_PASSWORD PLATFORM_RO_PASSWORD MONGO_ROOT_PASSWORD
GRAFANA_USER GRAFANA_PASSWORD MONGODB_URI
PINPOINT_MYSQL_ROOT_PASSWORD PINPOINT_MYSQL_PASSWORD PINPOINT_ADMIN_PASSWORD PINPOINT_SPRING_DATASOURCE_HIKARI_PASSWORD
PINPOINT_SPRING_METADATASOURCE_HIKARI_PASSWORD PINPOINT_WEB_SECURITY_AUTH_USER PINPOINT_WEB_SECURITY_AUTH_ADMIN PINPOINT_WEB_SECURITY_AUTH_JWT_SECRETKEY
MESSENGER_REPL_PASSWORD MESSENGER_RO_PASSWORD COMMERCE_REPL_PASSWORD COMMERCE_RO_PASSWORD GHOST_PASSWORD"
missing=""
for k in $REQUIRED; do
  case "$KEYS" in *" $k "*) ;; *) missing="$missing $k" ;; esac
done
[ -z "$missing" ] || { echo "필수 키가 없다:$missing" >&2; exit 1; }

# mysqld-exporter 의 .my.cnf — 메신저 MySQL 4쌍은 root/MYSQL_ROOT_PASSWORD, 커머스는 root/COMMERCE_DB_PASSWORD(auth_module=client.commerce)
umask 077
MY_CNF="$(mktemp "${TMPDIR:-/tmp}/my.cnf.XXXXXX")"
trap 'rm -f "$MY_CNF"' EXIT
{
  printf '[client]\nuser = root\npassword = %s\n\n' "$(value_of "$INFRA_ENV" MYSQL_ROOT_PASSWORD)"
  printf '[client.commerce]\nuser = root\npassword = %s\n' "$(value_of "$INFRA_ENV" COMMERCE_DB_PASSWORD)"
} > "$MY_CNF"

kubectl apply -f "$HERE/base/namespace.yaml" >/dev/null

kubectl -n "$NS" create secret generic infra "${ARGS[@]}" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic mongo-keyfile --from-file=mongodb.key="$MONGO_KEY" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic mysqld-exporter --from-file=.my.cnf="$MY_CNF" --dry-run=client -o yaml | kubectl apply -f -

# deploy-service 의 비밀값 2개. config-repo 는 공개 저장소라 {cipher} 로도 두지 않는다 — 여기 Secret 에만 둔다.
#   GITHUB_APP_PRIVATE_KEY  k8s/deploy-github-app.pem   PKCS#8 PEM(원본이 PKCS#1 이면 openssl pkcs8 -topk8 -nocrypt)
#   ARGOCD_TOKEN            k8s/argocd-deploy-token     Argo CD 로컬 계정 deploy 의 API 토큰(한 줄)
# 둘 다 없으면 Secret 을 만들지 않고, 하나만 있으면 그것만 담는다 — 없는 값은 빈 환경변수로 들어가고 그 기능만 멈춘다
# (앱 자격이 없으면 태그 커밋 불가, Argo 토큰이 없으면 Sync 불가. 기동 자체는 된다).
ARGS_DEPLOY=()
if [ -r "$APP_KEY" ]; then ARGS_DEPLOY+=(--from-file=GITHUB_APP_PRIVATE_KEY="$APP_KEY"); else echo "deploy-service: $APP_KEY 없음(태그 커밋 불가)" >&2; fi
if [ -r "$ARGO_TOKEN" ]; then
  # 파일 끝 줄바꿈이 값에 섞이면 Authorization 헤더가 깨진다 — 줄바꿈을 떼고 넣는다
  ARGS_DEPLOY+=(--from-literal=ARGOCD_TOKEN="$(tr -d '\r\n' < "$ARGO_TOKEN")")
else
  echo "deploy-service: $ARGO_TOKEN 없음(Argo Sync 불가)" >&2
fi
if [ ${#ARGS_DEPLOY[@]} -gt 0 ]; then
  kubectl -n "$NS" create secret generic deploy-service "${ARGS_DEPLOY[@]}" --dry-run=client -o yaml | kubectl apply -f -
  echo "deploy-service: 비밀값 ${#ARGS_DEPLOY[@]}개 반영"
fi
echo "Secret infra 키($(( $(echo "$KEYS" | wc -w) )))개:$KEYS"
