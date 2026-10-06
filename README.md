# modu_infra

modu 프로젝트(modu_messenger, modu_commerce)가 같이 쓰는 인프라와 관측성 스택, 그리고 그 위의 앱 계층을 Kubernetes 에 띄우는 매니페스트입니다.

이 저장소 옆에 다음 저장소가 clone 되어 있다고 가정합니다.

- modu_messenger — https://github.com/tear94fall/modu_chat (경로: `../modu_chat`)
- modu_commerce — https://github.com/tear94fall/modu_commerce (경로: `../modu_commerce`)
- modu_platform — https://github.com/tear94fall/modu_platform (경로: `../modu_platform`, config-repo 와 `.env`)

## 구성 (2026-10-03 부터 전부 k8s, 2026-10-06 부터 Colima)

dev 환경은 **앱도 인프라도 Colima(k3s, context `colima`, 네임스페이스 `modu`; 2026-10-06 까지는 Docker Desktop)** 에서 돈다. 매니페스트와 운영 절차는 [`k8s/README.md`](k8s/README.md).
compose 구성(`data/docker-compose.yml`, `monitoring/`, `pinpoint-docker/`)은 2026-10-04 에 저장소에서 지웠다 — 원본 설정이 궁금하면 git 이력(태그 없음, `git log -- monitoring`)을 본다.

| 디렉터리 | 내용 |
|---|---|
| `k8s/` | Kustomize 매니페스트 — `base/{platform,messenger,commerce,admin}` 앱 17개, `base/data`(MySQL 10, Redis, Redis 클러스터 6, ZooKeeper·Kafka·Debezium·kafka-ui, Mongo 3, MinIO, RabbitMQ), `base/observability`(OpenSearch·Dashboards, Prometheus·Grafana·exporter, Pinpoint, OTel Collector), `overlays/dev`, `cicd/argocd`(Argo CD + Application 2개 — dev 배포는 Argo Sync 로). Secret 의 원본은 `k8s/infra.env`·`k8s/mongodb.key`(gitignored, 틀은 `k8s/infra-secrets.example.env`) |
| `data/mysql/` | 스키마 기준선·변경 이력·gh-ost·DBA 절차 + k8s 운영 스크립트(복제 설정, gh-ost, 기준선 덤프, 고아 행 점검). 아래 "스키마 관리"·"운영 스크립트" |
| `data/mysql-commerce/` | `replica-setup.sh` — 커머스 복제 설정(공통 스크립트를 `commerce` 로 부르는 껍데기) |
| `data/kafka/` | 토픽 생성·조회·삭제 — `kubectl -n modu exec kafka-0 -- kafka-topics …` |
| `data/debezium/` | CDC 커넥터 등록·조회·삭제 — debezium 파드 안의 curl 로 Kafka Connect REST |

## 최초 준비 / 기동

```bash
kubectl config use-context docker-desktop
cd k8s
kubectl apply -f base/namespace.yaml
kubectl -n modu create secret generic config-service --from-literal=ENCRYPT_KEY=… --from-literal=INTERNAL_API_TOKEN=…   # modu_platform/.env 의 값
cp infra-secrets.example.env infra.env && $EDITOR infra.env   # 값 채우기(처음 한 번). mongodb.key 도 옆에(없으면 openssl rand -base64 756 > mongodb.key)
./create-infra-secret.sh                      # k8s/infra.env + k8s/mongodb.key → Secret infra·mongo-keyfile·mysqld-exporter
overlays/dev/gen-config-repo-configmaps.sh    # modu_platform/config-repo → ConfigMap
kubectl apply --server-side -k ceph && kubectl apply --server-side -k ceph    # Ceph(RGW = S3) — CRD 뒤에 CephCluster, 두 번
kubectl apply -k overlays/dev
```

Mac 에서 들어가는 포트(LoadBalancer): 게이트웨이 8000 · 콘솔 8081/8084/8085 · 커머스 웹 8082 · config 8888 · OpenSearch Dashboards 5601 · Grafana 3000 · Prometheus 19090 · Pinpoint 18080 · kafka-ui 9009 · Ceph RGW 7480 · Ceph 대시보드 7001 · RabbitMQ 15672. DB·Kafka·Redis 는 밖에 열지 않는다(`kubectl port-forward`, 또는 아래 운영 스크립트처럼 `kubectl exec`).

## 로그

서비스는 로그를 **stdout 에 한 줄 JSON**(logstash-logback-encoder)으로만 씁니다. `otel-collector` DaemonSet(`k8s/base/observability/otel-collector.yaml`)이 `/var/log/pods/modu_*` 를 읽어 OpenSearch 인덱스 `modu-app-logs` 로 보내고, `attributes.container`(컨테이너 이름)·`attributes.project: k8s` 를 붙입니다. JSON 줄은 필드를 풀고(`attributes.service`, `requestId` …), JVM 경고 같은 비 JSON 줄은 `body` 그대로입니다. (compose 시절엔 인프라 컨테이너 로그를 `modu-infra-logs` 로 나눴다 — k8s 에선 인프라 파드 로그는 `kubectl logs` 로 본다.)

- 대시보드: http://localhost:5601 (Discover → 인덱스 패턴 `modu-app-logs*`). dev 라 보안 플러그인은 꺼 두었다. 9200 도 LoadBalancer 로 열려 있다(로그 스크립트·curl 용).
- 모든 앱 로그 줄에 MDC 가 붙습니다: `requestId`(게이트웨이가 `X-Request-Id` 로 발급·전파), `userId`, `service`, Pinpoint `PtxId`/`PspanId`. 한 요청을 따라가려면 `attributes.requestId:<id>` 로 검색합니다. `PtxId` 로는 Pinpoint 의 호출 트리와 맞춰 볼 수 있습니다.
- 접근 로그: 모든 서비스가 `event:http.access`(method, path, status, durationMs) 한 줄. 커머스는 `event:api.access` 로 요청·응답 헤더·본문(민감 헤더 마스킹, 4KB 까지)까지 남깁니다.

## 스키마 관리

MySQL 스키마는 애플리케이션이 아니라 DBA 가 gh-ost 로 바꿉니다(서비스는 `ddl-auto: validate`). 기준선·변경 이력·절차는 `data/mysql/` 에 있습니다.

- `data/mysql/DBA.md` — 원칙(외래키 없음, 두 버전 공존), 변경 한 건의 흐름, 방법 선택 표, k8s 에서 gh-ost 돌리는 법
- `data/mysql/schema/*.sql` — 스키마 기준선 7개, `schema/changes/` — 변경 이력, `schema/checks/` — 고아 행 점검
- `data/mysql/ghost.sh` — gh-ost 실행(일회용 파드), `ghost-user-setup.sh` — gh-ost 계정, `dump-schema.sh` — 기준선 갱신, `check-orphans.sh` — 점검, `gh-ost/build-and-import.sh` — gh-ost 이미지를 노드에 넣기

## 운영 스크립트 (전부 k8s 기준 — `kubectl -n modu exec`)

공통: `NS=modu` 기본(환경변수로 바꿀 수 있다), 컨텍스트는 현재 kubectl 컨텍스트, `set -eu`. 비밀번호는 Secret `infra` 에서 읽고(`kubectl get secret infra -o jsonpath … | base64 -d`), MySQL root 는 파드 자신의 env `MYSQL_ROOT_PASSWORD` 를 파드 안에서 쓴다 — 화면에도 명령줄에도 안 찍는다.

- `data/kafka/{list,desc,create,delete}-topic.sh`: `kafka-0` 파드 안의 `kafka-topics --bootstrap-server localhost:9092`.
- `data/debezium/{list,create,delete}_connector.sh`: `deploy/debezium` 파드 안의 curl → `localhost:8083`. `create_connector.sh` 는 `mysql-chat:3306` 을 보고, 비밀번호(Secret `MYSQL_ROOT_PASSWORD`)는 JSON 본문을 stdin 으로 넘긴다.
- Mongo replica set 최초 구성: `kubectl -n modu exec mongo-01-0 -- bash /scripts/rs-init.sh` (ConfigMap `mongo-rs-init`, `k8s/base/data/mongo.yaml`. 최초 1회만 — 지금 데이터는 이미 구성돼 있다)
- `data/mysql/replica-setup.sh <대상>`: MySQL 읽기·쓰기 분리. 소스 파드 `mysql-<x>-0`(GTID·binlog ROW) → 레플리카 `mysql-<x>-replica-0` GTID 비동기 복제를 건다. 여러 번 돌려도 된다.
  - 대상: `member` `chat` `push` `profile` `commerce`, 묶음 `messenger`(앞의 넷) `all`. (`data/mysql-commerce/replica-setup.sh` 는 `commerce` 를 부르는 껍데기)
  - 복제 계정 `repl` 과 앱 읽기 계정(메신저 `modu_ro`, 커머스 `commerce_ro`, SELECT 만)을 소스에 만든다(복제로 레플리카에 전파). 비밀번호는 Secret `infra` 의 `MESSENGER_REPL_PASSWORD`·`MESSENGER_RO_PASSWORD`, `COMMERCE_REPL_PASSWORD`·`COMMERCE_RO_PASSWORD`.
  - 레플리카가 복제 중이 아니면 소스 DB 를 GTID 위치와 함께 덤프해(`kubectl exec` 소스 mysqldump → `kubectl exec -i` 레플리카 mysql, Mac 을 거쳐 간다) 적재한 뒤 `SOURCE_HOST=mysql-<x>`(Service), `SOURCE_AUTO_POSITION=1` 로 복제를 시작하고 `read_only`·`super_read_only` 를 `SET PERSIST` 로 켠다. 복제 중이면 계정만 맞춘다.
  - mysql-member 에는 `modu-chat`(회원)·`modu-point`(포인트)·`modu-schedule`(스케줄) 스키마가 함께 있다. 복제를 건 뒤 소스에서 만든 스키마는 복제로 따라온다.
  - 상태 확인: `kubectl -n modu exec mysql-member-replica-0 -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -e "SHOW REPLICA STATUS\G"'` (Replica_IO/SQL_Running, Seconds_Behind_Source)
  - `read_only` 를 레플리카 시작 옵션에 두면 이미지 첫 초기화가 root 비밀번호를 못 만든다 — 그래서 스크립트가 켠다.

## 주의사항

- `k8s/infra.env` 의 비밀번호는 PVC 에 저장된 현재 비밀번호와 같아야 합니다(MySQL healthcheck·exporter·앱이 사용). 바꾸려면 DB 쪽을 먼저 바꾸고 `create-infra-secret.sh` 를 다시 돌린 뒤 파드를 재시작합니다.
- PVC 를 지우면(StorageClass reclaim Delete) 데이터도 지워집니다. `kubectl delete -k overlays/dev` 는 PVC 를 지우지 않지만 StatefulSet 을 지우고 다시 만들 때 이름이 같아야 같은 PVC 에 붙습니다.
- compose 로 되돌릴 일이 있으면 옮기기 직전 백업(`~/modu-data/backup/2026-10-03-k8s/`)과 git 이력의 compose 파일을 쓴다.
