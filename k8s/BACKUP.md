# 백업·복구 런북

dev(Colima k3s)의 데이터는 전부 `local-path` PVC 에 있고 StorageClass 가 `Delete` 다 — `colima delete` 한 번으로 전부 사라진다.
그래서 **맥 디스크로** 매일 복사한다. 이 문서는 무엇이 어디로 가고, 잃었을 때 어떻게 되돌리는지만 적는다.

## 무엇이 어디로

| CronJob | 네임스페이스 | 시간(KST) | 내용 | 목적지 |
|---|---|---|---|---|
| `backup-mysql` | modu | 03:10 | 6개 인스턴스 `mysqldump`(레플리카에서) + 소스의 binlog 사본 | `<백업>/<날짜>/mysql-*.sql.gz`, `<백업>/<날짜>/binlog-*/` |
| `backup-mongo` | modu | 03:25 | `mongodump --archive --gzip`(세컨더리에서) | `<백업>/<날짜>/mongo.archive.gz` |
| `backup-rgw` | rook-ceph | 03:40 | 버킷을 `rclone copy`(누적 미러) | `<백업>/rgw/<버킷>/` |
| `backup-prune` | modu | 04:10 | 14일 지난 **날짜 디렉터리** 삭제(`rgw/` 는 건드리지 않는다) | — |

`<백업>` = dev 에서 **맥의 `~/modu-data/backup/auto`**. CronJob 은 `hostPath` 로 쓰고, Colima VM 이 맥 홈을 virtiofs 로 rw 마운트한다
(VM 안 root 로 쓴 파일이 맥에서는 내 소유로 보인다). 경로는 `k8s/overlays/dev/backup-path-patch.yaml` 이 정한다(base 는 자리표시자).

- 맥이 자고 있어 시간을 놓쳤으면 **깨어난 뒤 12시간 안에 한 번** 돈다(`startingDeadlineSeconds: 43200`). 그보다 늦으면 그날은 건너뛴다.
- 덤프는 쓰는 동안 `.part` 로 두고 끝나면 이름을 바꾼다 — `.part` 가 보이면 그 파일은 미완성이다.
- 손으로 한 번 돌리기: `kubectl -n modu create job --from=cronjob/backup-mysql now-mysql` (rgw 는 `-n rook-ceph`).
- 하루치 크기(2026-10-11 기준): MySQL 덤프 6개 83KB + binlog 28MB, Mongo 4.5KB, RGW 미러 20MB.

## 백업하지 않는 것(일부러)

- **Redis·Kafka·ZooKeeper·RabbitMQ** — 캐시·메시지 전달용. 잃으면 다시 채워진다(단, Kafka 아웃박스가 아직 안 보낸 이벤트는 사라진다).
- **OpenSearch 로그·Prometheus·Pinpoint** — 관측 데이터. 복구 대상이 아니다(수명 관리는 할 일 1-5).
- **Argo CD 상태** — 매니페스트가 Git 에 있으니 다시 만들면 된다.
- **비밀값** — 이 백업(평문으로 맥에 있다)에는 **일부러** 넣지 않는다. 암호를 걸어 따로 보관한다 → 아래 "비밀값".

## 비밀값

Git 에 없는 원본은 네 개뿐이고, 공개 저장소의 `{cipher}` 는 그중 `ENCRYPT_KEY` 로만 풀린다 — **맥을 잃으면 설정을 영영 못 푼다.**
`k8s/secrets-archive.sh` 가 그 넷 + RGW 사용자 키 + 되돌리는 순서(`INVENTORY.md`)를 **암호화 아카이브 하나**로 묶는다.

```bash
sh k8s/secrets-archive.sh --check        # 어떤 원본이 있는지만 본다(값은 읽지 않는다)
sh k8s/secrets-archive.sh                # 암호를 두 번 묻고 ~/modu-data/backup/secrets/modu-secrets-<날짜>.tar.gz.{age|enc} 생성
#  맥 밖으로 사본 한 부(권장):
SECRETS_ARCHIVE_COPY_TO="$HOME/Library/Mobile Documents/com~apple~CloudDocs/modu-secrets" sh k8s/secrets-archive.sh
sh k8s/secrets-archive.sh --restore <아카이브> [--to <디렉터리>]   # 풀기만 한다 — 저장소 파일을 덮어쓰지 않는다
```

- 담기는 것: `infra.env`(Secret `infra`·`mysqld-exporter`), `mongodb.key`(`mongo-keyfile`), `deploy-github-app.pem`(`deploy-service`),
  `modu_platform/.env`(`ENCRYPT_KEY`·`INTERNAL_API_TOKEN` → Secret `config-service`), `rgw-storage-service-keys.yaml`
  (**클러스터에만 있던 값** — `create-infra-secret.sh` 가 만들지 않는다. Ceph 를 다시 세울 때 이게 있어야 config-repo 를 안 건드린다).
- 암호는 **비밀번호 관리자**에. 스크립트는 암호를 어디에도 남기지 않고, 값을 화면에 찍지 않는다. 아카이브·보관 디렉터리는 600/700.
- `age` 가 있으면 age(인증 암호화), 없으면 `openssl enc -aes-256-cbc -pbkdf2 -iter 600000`. `brew install age` 를 권한다.
- **비밀값을 교체하면 다시 만든다**(옛 아카이브는 암호가 같아도 값이 낡는다). 만든 뒤 스크립트가 스스로 풀어 파일 목록을 보여 준다.

### 맥 자체 백업(Time Machine)

`tmutil destinationinfo` → **대상이 없다**(마운트 실패가 아니라 아예 설정되지 않았다). 외장 디스크나 네트워크 위치를 붙인 뒤
`sudo tmutil setdestination <경로>` 로 등록하고, 큰 임시 파일(Colima VM 이미지 `~/.lima`, Docker 데이터)은 제외 목록에 넣는다.
Time Machine 이 되면 위 아카이브와 `~/modu-data/backup` 이 맥 밖으로 한 번 더 복사된다.

## 복구

### MySQL 한 인스턴스
```bash
D=2026-10-11; I=platform                 # 날짜·인스턴스(member|chat|push|profile|commerce|platform)
PW=$(kubectl -n modu get secret infra -o jsonpath='{.data.PLATFORM_DB_PASSWORD}' | base64 -d)   # 메신저 4개는 MYSQL_ROOT_PASSWORD, 커머스는 COMMERCE_DB_PASSWORD
kubectl -n modu scale deploy/deploy-service --replicas=0          # 그 DB 를 쓰는 앱을 먼저 멈춘다
zcat ~/modu-data/backup/auto/$D/mysql-$I.sql.gz | kubectl -n modu exec -i mysql-$I-0 -- sh -c "MYSQL_PWD='$PW' mysql -uroot"
sh ~/workspace/modu_infra/data/mysql/replica-setup.sh $I          # 레플리카를 소스에서 다시 건다(덤프는 레플리카에서 떴다 ≠ 레플리카가 최신)
kubectl -n modu scale deploy/deploy-service --replicas=1
```
덤프는 `DROP TABLE IF EXISTS` + `CREATE TABLE` 이라 **같은 이름의 테이블을 덮어쓴다**(스키마 전체를 지우지는 않는다).
덤프 머리에 그 시점의 GTID 가 **주석**으로 있다(`--set-gtid-purged=COMMENTED`) — 시점 복구의 시작점이다.

### 시점 복구(PITR, 덤프 이후 ~지금)
```bash
D=2026-10-11; I=member
zcat ~/modu-data/backup/auto/$D/mysql-$I.sql.gz | head -40 | grep -i gtid_purged     # 덤프 시점 GTID(주석)
# 덤프를 올린 뒤, 그 뒤 트랜잭션만 binlog 사본에서 재생한다(--start-position 대신 GTID 로 거른다)
docker run --rm -v ~/modu-data/backup/auto/$D/binlog-$I:/b mysql:8.0.32-debian \
  mysqlbinlog --skip-gtids=false /b/mysql-bin.0000* > /tmp/after.sql     # 필요하면 --start-datetime/--stop-datetime 으로 자른다
```
binlog 사본은 **백업 시각까지**다(그 뒤 것은 다음 밤에 들어온다). 인스턴스 PVC 에는 7일치가 더 있다(`--binlog-expire-logs-seconds=604800`).

### Mongo
```bash
D=2026-10-11
U=$(kubectl -n modu get secret infra -o jsonpath='{.data.MONGODB_URI}' | base64 -d)
kubectl -n modu scale deploy/chat-store-service --replicas=0
kubectl -n modu exec -i mongo-01-0 -- mongorestore --uri="$U" --archive --gzip --drop < ~/modu-data/backup/auto/$D/mongo.archive.gz
kubectl -n modu scale deploy/chat-store-service --replicas=1
```

### RGW 버킷(첨부·사진)
```bash
kubectl -n rook-ceph get secret rgw-storage-service-keys -o jsonpath='{.data.AccessKey}' | base64 -d   # 자격(화면에 찍지 말 것)
# rclone 파드에서 되돌리기: rclone copy /backup/rgw/file-storage rgw:file-storage
```
`backup-rgw` 가 `copy`(동기화가 아니다)라 **지워진 객체도 사본에 남는다** — 실수로 지운 파일을 되돌릴 수 있다.

### 클러스터를 통째로 다시 만들 때
`k8s/README.md` 의 "옮긴 절차" 순서를 따른다(StorageClass → Secret → 인프라 → 덤프 적재 → 앱). 이 백업이 그 "덤프"다.

## 확인 기록

- **2026-10-11** 처음 만들며 네 CronJob 을 손으로 돌려 확인했다. 결과: 날짜 디렉터리 하나에 MySQL 6개 덤프 + binlog 6묶음, Mongo archive, RGW 미러 20MB.
- **복구를 실제로 해 봤다**(임시 파드에 복원 후 원본과 비교):
  - MySQL: 덤프 6개가 모두 적재됨. `modu-platform.deployment` = 소스 32행 / 레플리카 32행 / 복원본 32행, 최근 행 시각까지 같음.
  - Mongo: `modu-chat.chat` = 원본 105건 / 복원본 105건.
- 다음에 할 것: 이 확인을 분기마다 반복하고 결과를 여기 덧붙인다(연습하지 않은 복구는 복구가 아니다).
