#!/bin/sh
# secrets-archive.sh — Git 에 없는 비밀값을 암호화 아카이브 하나로 묶는다(할 일 1-2).
#
# 왜: 비밀값의 원본은 gitignored 파일 4개뿐이고, 공개 저장소의 {cipher} 는 modu_platform/.env 의 ENCRYPT_KEY 로만 풀린다.
#     맥을 잃으면 설정을 영영 못 푼다. 자동 백업(backup-* CronJob)에도 비밀값은 일부러 넣지 않는다 —
#     그 백업은 평문으로 맥에 있으니, 비밀값은 암호를 걸어 **따로** 보관한다.
#
# 쓰는 법
#   sh k8s/secrets-archive.sh                 # 아카이브 만들기(암호를 두 번 묻는다)
#   sh k8s/secrets-archive.sh --check         # 어떤 원본이 있는지만 본다(값은 읽지 않는다)
#   sh k8s/secrets-archive.sh --restore <파일> [--to <디렉터리>]
#   SECRETS_ARCHIVE_COPY_TO=~/Library/Mobile\ Documents/com~apple~CloudDocs/modu-secrets sh k8s/secrets-archive.sh
#
# 암호는 비밀번호 관리자에 둔다(이 스크립트는 암호를 저장하지 않는다). 값은 화면에 절대 찍지 않는다.
# 암호화는 age 가 있으면 age(인증 암호화), 없으면 openssl enc -aes-256-cbc -pbkdf2 로 한다(`brew install age` 를 권한다).
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_ENV="${PLATFORM_ENV:-$HOME/workspace/modu_platform/.env}"
OUT_DIR="${OUT_DIR:-$HOME/modu-data/backup/secrets}"
MODE=create; RESTORE_FILE=; RESTORE_TO=

while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE=check ;;
    --restore) MODE=restore; RESTORE_FILE="${2:?--restore <파일>}"; shift ;;
    --to) RESTORE_TO="${2:?--to <디렉터리>}"; shift ;;
    *) echo "모르는 인자: $1" >&2; exit 2 ;;
  esac
  shift
done

# 묶을 원본: "로컬경로|아카이브에서의 이름|설명"
SOURCES="
$HERE/infra.env|infra.env|Secret infra·mysqld-exporter 의 값 27개(DB·RabbitMQ·Grafana·Pinpoint 비밀번호). create-infra-secret.sh 가 읽는다
$HERE/mongodb.key|mongodb.key|Mongo 레플리카 셋 내부 인증 키(1024B). Secret mongo-keyfile
$HERE/deploy-github-app.pem|deploy-github-app.pem|deploy-service 의 GitHub App 비밀키(PKCS#8). Secret deploy-service
$PLATFORM_ENV|modu_platform.env|ENCRYPT_KEY(공개 저장소의 {cipher} 를 푸는 키) + INTERNAL_API_TOKEN. Secret config-service
"

if [ "$MODE" = check ]; then
  echo "▶ 원본 파일(값은 읽지 않는다)"
  echo "$SOURCES" | while IFS='|' read -r path name desc; do
    [ -n "${path:-}" ] || continue
    if [ -r "$path" ]; then echo "  ✓ $name  ($(wc -c < "$path" | tr -d ' ')B)  — $desc"
    else echo "  ✗ $name  없음: $path  — $desc"; fi
  done
  echo "▶ 클러스터에서 함께 담는 것"
  if kubectl -n rook-ceph get secret rgw-storage-service-keys >/dev/null 2>&1; then
    echo "  ✓ rgw-storage-service-keys.yaml — RGW(S3) 사용자 키. Ceph 를 다시 만들어도 버킷 자격이 그대로다"
  else
    echo "  ✗ rgw-storage-service-keys 없음(클러스터가 꺼져 있으면 건너뛴다)"
  fi
  echo "▶ 아카이브 위치: $OUT_DIR"
  ls -l "$OUT_DIR" 2>/dev/null | sed 's/^/  /' || echo "  (아직 없음)"
  exit 0
fi

# 암호화 도구 고르기
if command -v age >/dev/null 2>&1; then TOOL=age; EXT=tar.gz.age
else TOOL=openssl; EXT=tar.gz.enc; fi

if [ "$MODE" = restore ]; then
  [ -r "$RESTORE_FILE" ] || { echo "읽을 수 없다: $RESTORE_FILE" >&2; exit 1; }
  DEST="${RESTORE_TO:-$(mktemp -d "${TMPDIR:-/tmp}/modu-secrets.XXXXXX")}"
  mkdir -p "$DEST"; chmod 700 "$DEST"
  case "$RESTORE_FILE" in
    *.age) command -v age >/dev/null 2>&1 || { echo "age 가 필요하다: brew install age" >&2; exit 1; }
           age -d "$RESTORE_FILE" | tar -xzf - -C "$DEST" ;;
    *.enc) printf '암호: ' >&2; stty -echo 2>/dev/null || true; read -r PASS; stty echo 2>/dev/null || true; echo >&2
           PASS="$PASS" openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha512 -pass env:PASS -in "$RESTORE_FILE" | tar -xzf - -C "$DEST" ;;
    *) echo "모르는 확장자: $RESTORE_FILE" >&2; exit 2 ;;
  esac
  chmod -R go-rwx "$DEST"
  echo "▶ 풀었다: $DEST"
  ls -l "$DEST" | sed 's/^/  /'
  echo "  (되돌리는 순서는 INVENTORY.md 를 본다. 저장소 파일을 덮어쓰지는 않았다)"
  exit 0
fi

# ---- 만들기 ----
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/modu-secrets-stage.XXXXXX")"
chmod 700 "$STAGE"
trap 'rm -rf "$STAGE"' EXIT INT TERM

MISSING=0
echo "$SOURCES" | while IFS='|' read -r path name desc; do
  [ -n "${path:-}" ] || continue
  if [ -r "$path" ]; then cp "$path" "$STAGE/$name"; echo "  + $name"
  else echo "  ! $name 없음: $path" >&2; fi
done
for f in infra.env mongodb.key deploy-github-app.pem modu_platform.env; do
  [ -e "$STAGE/$f" ] || MISSING=1
done
[ "$MISSING" = 0 ] || echo "  (일부 원본이 없다 — --check 로 확인하고, 일부러 빠진 게 아니면 멈추고 고칠 것)" >&2

# Ceph RGW 사용자 키는 클러스터에만 있다(create-infra-secret.sh 가 만들지 않는다) — 있으면 함께 담는다
if kubectl -n rook-ceph get secret rgw-storage-service-keys -o yaml > "$STAGE/rgw-storage-service-keys.yaml" 2>/dev/null; then
  echo "  + rgw-storage-service-keys.yaml"
else
  rm -f "$STAGE/rgw-storage-service-keys.yaml"
  echo "  ! rgw-storage-service-keys 를 못 읽었다(클러스터 꺼짐?) — 나중에 다시 만들 것" >&2
fi

cat > "$STAGE/INVENTORY.md" <<'MD'
# 이 아카이브 안의 것과 되돌리는 순서

| 파일 | 어디로 | 쓰는 곳 |
|---|---|---|
| `infra.env` | `modu_infra/k8s/infra.env` | `k8s/create-infra-secret.sh` → Secret `infra`, `mysqld-exporter` |
| `mongodb.key` | `modu_infra/k8s/mongodb.key` | 같은 스크립트 → Secret `mongo-keyfile` |
| `deploy-github-app.pem` | `modu_infra/k8s/deploy-github-app.pem` | 같은 스크립트 → Secret `deploy-service`(GitHub App 비밀키) |
| `modu_platform.env` | `modu_platform/.env` | `ENCRYPT_KEY`(공개 저장소 `{cipher}` 복호화) + `INTERNAL_API_TOKEN` → Secret `config-service` |
| `rgw-storage-service-keys.yaml` | `kubectl apply -f` (네임스페이스 rook-ceph) | RGW(S3) 사용자 키 — Ceph 를 다시 만들어도 버킷 자격 유지 |

순서:
1. 파일들을 위 경로에 되돌린다(권한 600).
2. `cd modu_infra/k8s && ./create-infra-secret.sh` → Secret 4개.
3. `kubectl -n modu create secret generic config-service --from-literal=ENCRYPT_KEY=… --from-literal=INTERNAL_API_TOKEN=…`
   (값은 `modu_platform.env` 에서. `k8s/README.md` "처음 한 번" 1)번과 같다)
4. Ceph 를 새로 세웠다면 `kubectl apply -f rgw-storage-service-keys.yaml` 을 **Ceph 설치 전에** 해 둔다.
5. 데이터 복구는 `k8s/BACKUP.md`.

바꿨을 때: 비밀값을 교체하면 이 아카이브를 **다시 만든다**(`sh k8s/secrets-archive.sh`). 옛 아카이브는 암호가 같아도 값이 낡는다.
MD
echo "  + INVENTORY.md"

mkdir -p "$OUT_DIR"; chmod 700 "$OUT_DIR"
STAMP="$(date +%Y-%m-%d)"
ARCHIVE="$OUT_DIR/modu-secrets-$STAMP.$EXT"

echo "▶ 암호화($TOOL) → $ARCHIVE"
if [ "$TOOL" = age ]; then
  tar -czf - -C "$STAGE" . | age -p -o "$ARCHIVE"          # age 가 암호를 두 번 묻는다
else
  printf '암호: ' >&2;      stty -echo 2>/dev/null || true; read -r PASS;  stty echo 2>/dev/null || true; echo >&2
  printf '한 번 더: ' >&2;  stty -echo 2>/dev/null || true; read -r PASS2; stty echo 2>/dev/null || true; echo >&2
  [ "$PASS" = "$PASS2" ] || { echo "암호가 다르다" >&2; exit 1; }
  tar -czf - -C "$STAGE" . | PASS="$PASS" openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha512 -salt -pass env:PASS -out "$ARCHIVE"
fi
chmod 600 "$ARCHIVE"

echo "▶ 되돌려 풀어 확인(파일 이름만 본다)"
if [ "$TOOL" = age ]; then
  echo "  (age 는 확인할 때도 암호를 묻는다)"
  age -d "$ARCHIVE" | tar -tzf - | sed 's/^/  /'
else
  PASS="$PASS" openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha512 -pass env:PASS -in "$ARCHIVE" | tar -tzf - | sed 's/^/  /'
fi

shasum -a 256 "$ARCHIVE" | sed 's/^/  sha256 /'
ls -l "$ARCHIVE" | sed 's/^/  /'

if [ -n "${SECRETS_ARCHIVE_COPY_TO:-}" ]; then
  mkdir -p "$SECRETS_ARCHIVE_COPY_TO"
  cp "$ARCHIVE" "$SECRETS_ARCHIVE_COPY_TO/"
  echo "▶ 사본: $SECRETS_ARCHIVE_COPY_TO/$(basename "$ARCHIVE")"
fi

cat <<MSG
▶ 남은 일(사람이 해야 한다)
  1. 암호를 비밀번호 관리자에 저장한다(이 스크립트는 암호를 어디에도 남기지 않는다).
  2. 아카이브를 **맥 밖**으로 한 부 옮긴다 — iCloud Drive, 다른 기기, 외장 디스크 중 하나.
     예) SECRETS_ARCHIVE_COPY_TO="\$HOME/Library/Mobile Documents/com~apple~CloudDocs/modu-secrets" 로 다시 실행
  3. 비밀값을 교체할 때마다 다시 만든다.
MSG
