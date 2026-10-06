# k8s — modu 전체(앱 + 인프라) Kustomize 매니페스트

modu 의 **앱 계층**(플랫폼 2 + 메신저 10 + 커머스 2 + 콘솔 3 = Deployment 17개)과 **인프라 전부**(MySQL×10, Redis, Redis 클러스터×6, ZooKeeper·Kafka·Debezium·Kafka UI, Mongo×3, Ceph(RGW), RabbitMQ, OpenSearch·Dashboards, Prometheus·Grafana·exporter 4개, Pinpoint)를 로컬 **Colima**(k3s, context `colima`, 1 노드, 네임스페이스 `modu` 하나 — 2026-10-06 까지는 Docker Desktop)에 띄우는 매니페스트입니다. 아래 [Colima](#colima-2026-10-06-부터).
인프라의 Service 이름·포트는 compose 컨테이너 이름·포트와 같다(`mysql-chat:3306`, `kafka:9092`, `redis-node-1:6379` …) — 그래서 앱 설정(config-repo, env)은 compose 때와 그대로다. 인프라는 2026-10-03 에 compose 에서 옮겼다(아래 [인프라도 k8s](#인프라도-k8s)).

```
k8s/
  base/                              # 환경 공통. namespace modu, 공통 라벨 app.kubernetes.io/part-of=modu
    namespace.yaml
    platform/   config-service.yaml gateway-service.yaml deploy-service.yaml   # config·gateway replicas 2; deploy-service = 배포 탭 백엔드(SA+Role 읽기 전용)
    messenger/  auth member chat chat-store ws push storage profile point schedule (-service.yaml)
    commerce/   commerce-service.yaml web.yaml
    admin/      modu-admin.yaml modu-system.yaml modu-internal.yaml
    data/       mysql.yaml(10) mysql-platform.yaml(deploy-service 이력 DB) redis.yaml redis-cluster.yaml(6 + init Job) kafka.yaml(zookeeper·kafka·debezium·kafka-ui) mongo.yaml(3) rgw.yaml(ExternalName → ceph/) rabbitmq.yaml
    observability/  opensearch.yaml(+dashboards) otel-collector.yaml(파드 로그 DaemonSet) prometheus.yaml(+RBAC) grafana.yaml(+grafana/dashboards/*.json)
                    exporters.yaml(mysqld·redis·mongodb·kafka) pinpoint.yaml(hbase·mysql·redis·zoo1·collector·web)
  overlays/dev/
    kustomization.yaml               # images(태그), replicas, 아래 생성 파일
    loadbalancers.yaml               # Mac 에서 들어오는 입구: 앱 6개 + 인프라 UI 8개(compose 와 같은 호스트 포트)
    storageclass.yaml                # k3s 용 StorageClass `standard`(local-path) — base 의 PVC 이름을 안 바꾸려고
    colima-ports.sh                  # LB 포트를 Mac(localhost·LAN IP)으로 내보내는 nginx(stream) 컨테이너
    pinpoint-agent-patch*.yaml       # JVM Deployment 에 Pinpoint 에이전트(init 컨테이너 + JDK_JAVA_OPTIONS) — dev 는 2026-10-04 부터 꺼 둠(아래 "Pinpoint 켜기/끄기")
  cicd/argocd/                       # Argo CD(v3.5.3) 설치 + Application 3개(modu-dev, modu-config-repo, modu-ceph) — 아래 "Argo CD 로 배포"
  ceph/                              # Rook-Ceph(RGW = S3, MinIO 대체) — 아래 "Ceph"
    secret.example.yaml              # Secret config-service 의 틀(값 비어 있음) — kustomization 에 없음
  create-infra-secret.sh             # infra.env + mongodb.key → Secret infra, mongo-keyfile, mysqld-exporter
  infra-secrets.example.env          # Secret infra 의 키 목록(값 비어 있음) — infra.env 로 복사해 채운다
  infra.env, mongodb.key             # (gitignored) Secret 의 원본 값·mongo keyFile
```

## Colima (2026-10-06 부터)

Docker Desktop(VM 28GB 예약 + 헬퍼 프로세스)이 Mac(32GB)을 잡아먹어 **Colima**(Lima VM + docker + k3s, 전부 CLI)로 바꿨다. 앱 코드·config-repo 는 안 바뀌었고 매니페스트는 StorageClass 하나와 포트 포워딩 스크립트만 늘었다.

```bash
brew install colima                                   # docker CLI·kubectl 은 이미 있음
colima start --cpu 8 --memory 20 --disk 120 --vm-type vz --mount-type virtiofs --kubernetes --network-address --network-host-addresses
#   k3s v1.35(docker 런타임 공유 → docker build 한 이미지를 k8s 가 바로 본다), VM IP 192.168.64.x, context colima. 두 번째부터는 `colima start` 만.
colima stop | colima status | colima ssh -- free -m     # 멈추기·상태·VM 안
```

| 항목 | Docker Desktop | Colima(k3s) |
|---|---|---|
| StorageClass | `standard`(local-path) | 기본은 `local-path` → `overlays/dev/storageclass.yaml` 이 같은 provisioner 로 `standard` 를 만든다. PV 데이터는 VM 안 `/var/lib/rancher/k3s/storage/` |
| LoadBalancer | Mac 의 모든 인터페이스로 열림 | ServiceLB 가 **VM IP**(192.168.64.3)에 연다. Mac 의 localhost·LAN IP 로 쓰려면 **`overlays/dev/colima-ports.sh`**(docker 로 nginx stream 컨테이너, 포트 15개를 VM IP 로 중계; Lima 가 docker 가 듣는 포트를 Mac 0.0.0.0 으로 포워딩) — VM 을 새로 만들면 다시. 안드로이드 앱의 `192.168.0.3:8000`, OAuth issuer 도 그대로 |
| 로컬 이미지 | `docker save \| ctr import` | `docker build` 만(`data/mysql/gh-ost/build-and-import.sh`) |
| NetworkPolicy | kindnet 이 강제(사고) | flannel, 강제 없음 — Argo 의 NetworkPolicy 삭제 패치는 그대로 둬도 된다 |
| Ceph | loop + udev DB 꼼수 | VM 에 udevd 가 있어 udev 꼼수는 불필요(DaemonSet 은 그대로, 무해). loop 디스크는 여전히 필요 |
| 메모리 | VM 28GB | VM 20GB(스택 사용 ≈ 13~15GB). 모자라면 `colima stop && colima start --memory 22` |

**옮긴 절차(2026-10-06)** — 다시 만들 때(`colima delete` 뒤)도 같다:
1. Docker Desktop 에서 덤프: MySQL 5 소스(`mysqldump --databases … --set-gtid-purged=OFF`), Mongo(`mongodump --archive --gzip`), Ceph 버킷(rclone 파드 → tar), RGW 사용자 키(Secret), Dashboards 저장 객체(`/api/saved_objects/_export`) → `~/modu-data/backup/2026-10-06-colima/`.
2. `colima start …` → `kubectl apply -f overlays/dev/storageclass.yaml` → `kubectl create ns modu` → `./create-infra-secret.sh` + Secret `config-service` → `kubectl apply -k overlays/dev` 하고 **앱 Deployment 17개는 replicas 0** 으로(인프라 먼저).
3. Argo(`cicd/argocd`, 두 번), Ceph(`k8s/ceph`, 두 번; 그 전에 Secret `rgw-storage-service-keys` 를 백업 키로 만들면 RGW 사용자 키가 그대로라 config-repo 를 안 건드린다).
4. MySQL 덤프 적재 → `sh data/mysql/replica-setup.sh all` → Mongo `kubectl -n modu exec mongo-01-0 -- bash /scripts/rs-init.sh` + `mongorestore --nsExclude 'admin.*'` → Ceph 버킷 rclone 파드로 복원 → Dashboards `_import`.
5. `kubectl apply -k ~/workspace/modu_platform`(config-repo ConfigMap) → 앱을 config → gateway → 3개씩 순서로 replicas 1 → `colima-ports.sh` → Argo 세 Application Sync(입양) → Flip3 확인.

**밟은 것**: ① Docker Desktop 을 "종료"해도 `com.docker.backend` 가 남아 8000·8090 을 잡고 있었다 — `pkill -f com.docker.backend`. ② Lima 는 "소켓으로 듣는" 게스트 포트만 포워딩하므로 k3s ServiceLB(iptables) 포트는 Mac 에 안 보인다 → `colima-ports.sh`. ③ kustomize 원격 URL(Argo 공식 매니페스트)은 이미지 받는 중엔 git fetch 가 27초 타임아웃에 걸린다 — 재시도. ④ VM 에는 `$HOME` 만 마운트돼 있어 `mktemp`(/var/folders)로 만든 파일을 `docker -v` 로 못 넘긴다. ⑤ Rook 이 만드는 Secret `rook-ceph-object-user-modu-storage-service` 의 키가 실제 RGW 사용자 키(고정한 값)와 달랐다 — 실제 키는 `radosgw-admin --rgw-realm=modu --rgw-zonegroup=modu --rgw-zone=modu user info --uid=storage-service`(operator 파드)로 본다. config-repo 는 고정한 키라 맞다.

## dev 의 기본 실행 환경 (2026-10-03 부터)

dev 는 **전부 k8s 에서 돈다.** 처음(2026-10-03 오전)엔 앱 계층만 옮기고 인프라는 compose 에 둔 채 headless Service + Endpoints(`gen-infra-endpoints.sh`, 지금은 없음)로 이었고, 같은 날 인프라도 옮겼다. compose 스택(`data/docker-compose.yml`, `monitoring/`, `pinpoint-docker/`, 앱 4개)은 내린 뒤 2026-10-04 에 저장소에서도 지웠다(git 이력에만 있다). 둘을 같이 띄울 메모리가 없다(Docker VM 24GB).

- **입구**: (Colima 에선 `colima-ports.sh` 가 같은 포트를 Mac 으로 연다 — 위 "Colima".) Docker Desktop 시절: NodePort 는 localhost 로 안 나오지만 **LoadBalancer Service 는 Mac 의 모든 인터페이스(*:포트)로 열렸다.** compose 가 쓰던 포트 그대로라 앱·콘솔·웹 주소가 안 바뀐다 — 게이트웨이 8000(안드로이드는 `192.168.0.3:8000`), 콘솔 8081/8084/8085, 커머스 웹 8082, config-service 8888(dev 도구용).
- **로그**: `otel-collector` DaemonSet 이 `/var/log/pods/modu_*` 를 읽어 compose 와 같은 OpenSearch 인덱스 `modu-app-logs` 로 보낸다(`attributes.project: k8s`, `attributes.container`).
- **Pinpoint**: **dev 에선 꺼 둔다(2026-10-04 결정 — APM 은 운영 환경에서만, dev 는 필요할 때 켠다; 메모리 상한 약 4.6GiB 를 Argo CD·GoCD 자리로).** 켜는 법은 아래 "Pinpoint 켜기/끄기". 켜면: JVM 13개에 에이전트(컬렉터와 같은 3.1.0, init 컨테이너가 jar 를 복사). 로그 MDC 옵션은 `-Dpinpoint.profiler.logback.logging.transactioninfo=true` 로 덮어써지지만 컬렉터 주소(`profiler.transport.grpc.collector.ip`, 기본 127.0.0.1)는 `-D` 로 안 바뀌어서 init 컨테이너가 설정 파일을 `pinpoint-collector` 로 고친다(`overlays/dev/pinpoint-agent-patch*.yaml`).
- **롤아웃은 한 번에 하나씩.** (Argo CD 로 Sync 하면 JVM Deployment 의 `sync-wave` 1~13 이 이 순서를 자동으로 지킨다 — 아래 "Argo CD 로 배포". 손으로 `kubectl apply -k` 할 때만 아래 절차.) 단일 노드·빠듯한 메모리에서 13개 Deployment 의 pod 템플릿을 한꺼번에 바꾸면(공통 패치 수정 + `apply -k`) maxSurge 1 때문에 JVM 이 26개가 되어 노드가 멈춘다(2026-10-03 실제로 API 서버가 응답 불능). 공통 변경은:
  ```bash
  J=(config-service gateway-service auth-service member-service chat-service chat-store-service ws-service push-service profile-service storage-service point-service schedule-service commerce-service)
  kubectl -n modu rollout pause deploy "${J[@]}"      # zsh 는 $J 를 단어로 안 나눈다 — 배열로
  kubectl apply -k overlays/dev
  for d in "${J[@]}"; do kubectl -n modu rollout resume deploy/$d; kubectl -n modu rollout status deploy/$d; done
  ```
  이미지 태그 하나만 바꾸는 평소 배포는 그 Deployment 하나만 굴러가므로 그냥 `apply -k` 하면 된다.
- **compose 는 없다**: 2026-10-03 밤에 compose 컨테이너·볼륨·네트워크를 전부 지웠고, 2026-10-04 에 저장소의 compose 파일(`data/docker-compose.yml`, `monitoring/`, `pinpoint-docker/`, `data/mongodb/`)도 지웠다. 되돌릴 일이 있으면 옮기기 직전 백업(`~/modu-data/backup/2026-10-03-k8s/`: MySQL 5개 전체 덤프, Mongo 아카이브, MinIO 파일, Grafana 데이터)과 git 이력의 compose 파일로 다시 올린다. 저장소의 `data/` 에는 스키마(`data/mysql/schema`)와 k8s 기준 운영 스크립트만 남아 있다.

## 매니페스트 요약

| 항목 | 값 |
|---|---|
| 이미지 | `ghcr.io/tear94fall/modu-chat/<svc>`, `modu-platform/<svc>`, `modu-commerce/{commerce-service,web}`, `modu-admin/{modu-admin,modu-system,modu-internal}` — base 는 `develop`, 오버레이 `images:` 로 고정. `imagePullPolicy: IfNotPresent`, 공개 패키지라 imagePullSecrets 없음 |
| Service | ClusterIP, 이름·포트 = compose 컨테이너 이름·포트 = config-repo `modu.services.*` (auth 9900, member 8080(+8082 management), chat 9090, chat-store 8100, ws 8090, push 9990, storage 9999, profile 8880, point 9600, schedule 8110, commerce 8200, config 8888, gateway 8000) |
| env | `CONFIG_SERVER_URI=http://config-service:8888`; JPA 6개(chat·member·point·profile·push·schedule)는 `SPRING_DATASOURCE_{MASTER,REPLICA}_{URL,USERNAME}` (compose 의 `spring.datasource.master.url` 과 같은 값 — 점이 든 이름은 k8s env 이름으로 못 써서 relaxed-binding 형태); storage 는 `MINIO_ENDPOINT`; gateway 는 `ADMIN_ALLOWED_ORIGIN`; config 는 Secret 의 `ENCRYPT_KEY`·`INTERNAL_API_TOKEN` + `RABBITMQ_HOST` |
| probe | startup: readiness 경로 5s×30 → readiness `/actuator/health/readiness`(20s 뒤 10s 마다, 6회) → liveness `/actuator/health/liveness`(60s 뒤 15s 마다, 3회). member-service 는 8082. nginx 는 `GET /` |
| resources | JVM: requests 512Mi/250m, limits 1Gi(member·commerce 1280Mi), CPU limit 없음(compose `mem_reservation`/`mem_limit` 과 같음). nginx: 16Mi/50m, 64Mi |
| 롤아웃 | RollingUpdate maxSurge 1 / maxUnavailable 0, `terminationGracePeriodSeconds 30`(graceful shutdown 20s) |
| 보안 | `runAsNonRoot: false` — 이미지가 아직 root 로 돈다(후속) |
| config-repo | ConfigMap `config-repo-root`·`config-repo-messenger`·`config-repo-commerce` 를 `/config-repo`, `/config-repo/messenger`, `/config-repo/commerce` 에 마운트(키에 `/` 를 못 써서 디렉터리마다 하나). 값은 전부 `{cipher}` 라 비밀 아님 |

## 처음 한 번

```bash
cd ~/workspace/modu_infra/k8s
kubectl config use-context docker-desktop

# 1) 네임스페이스 + Secret (config-service 의 복호화 키·내부 토큰. 값은 modu_platform/.env 와 같아야 한다)
kubectl apply -f base/namespace.yaml
set -a; source ~/workspace/modu_platform/.env; set +a
kubectl -n modu create secret generic config-service \
  --from-literal=ENCRYPT_KEY="$ENCRYPT_KEY" --from-literal=INTERNAL_API_TOKEN="$INTERNAL_API_TOKEN"

# 2) 인프라 Secret(infra, mongo-keyfile, mysqld-exporter) — k8s/infra.env + k8s/mongodb.key(둘 다 gitignored)에서. 다시 돌려도 된다(apply)
cp infra-secrets.example.env infra.env && $EDITOR infra.env      # 처음 한 번: 23개 값 채우기(키마다 주석). mongodb.key 가 없으면 openssl rand -base64 756 > mongodb.key
./create-infra-secret.sh

# 3) Ceph(RGW) — 아래 "Ceph" 절(두 번 apply, 5~10분)
kubectl apply --server-side -k ceph; sleep 5; kubectl apply --server-side -k ceph

# 4) 생성 파일
overlays/dev/gen-config-repo-configmaps.sh   # ~/workspace/modu_platform/config-repo (CONFIG_REPO 로 바꿀 수 있다)

# 5) 확인 후 적용 (compose 에서 처음 옮길 때는 아래 '인프라도 k8s → 처음 옮길 때 순서' 를 먼저)
kubectl kustomize overlays/dev > /dev/null
kubectl apply --dry-run=client -k overlays/dev
kubectl apply -k overlays/dev
kubectl -n modu rollout status deploy/config-service --timeout=5m   # 나머지는 config 가 뜰 때까지 fail-fast 로 재시작하다가 따라 올라온다
kubectl -n modu rollout status deploy --timeout=10m
kubectl -n modu get pods -o wide
```

`kubectl apply -k` 를 한 번에 돌려도 된다. 서비스는 config-service 를 못 만나면 기동에 실패(`spring.cloud.config.fail-fast`)하고 CrashLoopBackOff 로 재시도하므로 config 가 뜨면 자연히 따라온다. Secret 이 없으면 config-service 파드가 `CreateContainerConfigError` 로 기다리다 Secret 이 생기면 바로 뜬다.

메모리 requests 합은 앱 약 7.1GiB(JVM 14개×512Mi + nginx 4개×16Mi) + 인프라 약 10.6GiB(아래 표) ≈ 17.7GiB, 노드 allocatable 은 약 27.4GiB(`kubectl describe node desktop-control-plane | grep -A8 Allocated`). limits 합(앱 ~14.1GiB + 인프라 ~22.9GiB)은 노드보다 크다 — 전부가 한꺼번에 limit 까지 쓰지는 않는다는 가정(overcommit). 모자라면 Pending 이 되니 Docker Desktop 의 메모리를 올리거나 오버레이 `replicas:` 를 줄인다.

## 포트 — Mac 에서 들어오는 길

`overlays/dev/loadbalancers.yaml` 의 LoadBalancer Service 가 Mac 의 모든 인터페이스에 compose 와 **같은 포트**로 열린다(Docker Desktop 은 NodePort 는 localhost 로 안 내보낸다). 안드로이드 기기는 Mac 의 LAN IP(`192.168.0.3`).

| URL | 대상 |
|---|---|
| http://localhost:8000 | gateway-service (앱 API, `/auth-service/**`, `/member-service/**` …) |
| http://localhost:8082 | modu-commerce-web (nginx → gateway) |
| http://localhost:8081 / 8084 / 8085 | modu-admin / modu-system / modu-internal 콘솔 |
| http://localhost:8888 | config-service (dev 도구용 — 토큰 발급 스크립트 등) |
| http://localhost:5601 | OpenSearch Dashboards (로그) |
| http://localhost:9200 | OpenSearch API (로그 스크립트·curl. compose 는 127.0.0.1 에만 열었지만 LoadBalancer 는 모든 인터페이스) |
| http://localhost:3000 | Grafana |
| http://localhost:19090 | Prometheus (→ 9090) |
| http://localhost:9009 | Kafka UI (→ 8080) |
| http://localhost:18080 | Pinpoint Web (→ 8080) |
| http://localhost:7480 / 7001 | Ceph RGW(S3) / Ceph 대시보드 |
| http://localhost:15672 | RabbitMQ 관리 화면 |

개별 서비스 포트(9900, 8080 …)와 **MySQL·Mongo·Redis·Kafka** 는 바깥에 열지 않는다. 필요하면 port-forward:

```bash
kubectl -n modu port-forward svc/member-service 8080:8080
kubectl -n modu port-forward svc/mysql-member 3306:3306        # compose 때 호스트 포트: member 3306, chat 3307, push 3308, profile 3309, commerce 3316 (+20 = replica, commerce-replica 3317)
kubectl -n modu port-forward svc/mongo-01 27017:27017
kubectl -n modu port-forward svc/redis 6379:6379
```
Redis 클러스터와 Kafka 는 port-forward 로는 못 쓴다(노드·브로커가 클러스터 안의 이름 `redis-node-N`·`kafka:9092` 를 광고한다) — `kubectl -n modu exec -it redis-node-1-0 -- redis-cli -c`, `kubectl -n modu exec -it kafka-0 -- kafka-topics --bootstrap-server kafka:9092 --list` 처럼 파드 안에서. 토픽·Debezium 커넥터·MySQL 복제·gh-ost 는 `data/kafka`, `data/debezium`, `data/mysql` 의 스크립트가 그렇게 돈다(루트 README "운영 스크립트").

## 인프라도 k8s

2026-10-03 에 compose 의 인프라(`data/docker-compose.yml`, `monitoring/`, `pinpoint-docker/` — 2026-10-04 에 저장소에서 지움)를 `base/data`, `base/observability` 로 옮겼다. 네임스페이스는 앱과 같은 `modu` 하나.
**Service 이름·포트 = compose 컨테이너 이름·포트** 라서 앱 설정은 하나도 안 바뀐다. 이름이 정확히 `mysql-member` 여야 해서 상태 있는 것은 인스턴스마다 replicas 1 짜리 StatefulSet 이고, Service 는 ClusterIP — 단, `mongo-01..03` 은 **헤드리스 + `publishNotReadyAddresses`**(mongod 가 기동 중에 복제셋 설정의 자기 이름을 파드 IP 로 풀어야 멤버로 인식한다. ClusterIP 면 "not a member" 로 서지 않는다). 볼륨은 `volumeClaimTemplates`(StorageClass `standard` = local-path, 노드 디스크; **reclaim Delete — PVC 를 지우면 데이터도 지워진다**).

| 구성 요소 | 종류 | 이미지 | Service:포트 | PVC | 메모리 req / limit |
|---|---|---|---|---|---|
| mysql-{member,chat,push,profile} + `-replica` | STS ×8 | mysql:8.0.32 | :3306 | 2Gi | 384Mi / 768Mi |
| mysql-platform | STS | mysql:8.0.32 | :3306 | 1Gi | 256Mi / 512Mi | 플랫폼 서비스용(2026-10-07): deploy-service 배포 이력 `modu-platform.deployment`. 단일 인스턴스, 초기 스키마는 ConfigMap mysql-platform-init, 계정 platform(PLATFORM_DB_*) |
| mysql-commerce(-replica) | STS ×2 | mysql:8.0.44 | :3306 | 2Gi | 384Mi / 768Mi |
| redis | STS | redis:7.2.4-alpine | :6379 | 256Mi | 32Mi / 128Mi |
| redis-node-1..6 | STS ×6 + Job `redis-cluster-init` | redis:7.4.11-alpine | :6379, :16379 | 256Mi | 32Mi / 128Mi |
| zookeeper | STS | confluentinc/cp-zookeeper:7.6.1 | :2181 | data 1Gi + log 2Gi | 128Mi / 384Mi |
| kafka | STS | confluentinc/cp-kafka:7.6.1 | :9092 | 5Gi | 512Mi / 1Gi |
| debezium | Deploy | debezium/connect:2.5.0.Final | :8083 | — | 256Mi / 768Mi |
| kafka-ui | Deploy | provectuslabs/kafka-ui:v0.7.2 | :8080 | — | 256Mi / 512Mi |
| mongo-01..03 | STS ×3 | mongo:7.0.8 | :27017 | 2Gi | 256Mi / 768Mi |
| (minio) | — | 2026-10-05 Ceph RGW 로 교체(k8s/ceph, 네임스페이스 rook-ceph) | | | |
| rabbitmq | STS | rabbitmq:3.12.4-management | :5672, :15672, :25672, :15692 | 512Mi | 128Mi / 384Mi |
| opensearch | STS | opensearchproject/opensearch:3.3.2 | :9200 | 5Gi | 1.5Gi / 1.5Gi |
| opensearch-dashboards | Deploy | opensearchproject/opensearch-dashboards:3.3.0 | :5601 | — | 256Mi / 768Mi |
| otel-collector | DaemonSet | otel/opentelemetry-collector-contrib:0.141.0 | — | — | 64Mi / 256Mi |
| prometheus | STS | prom/prometheus:v3.14.0 | :9090 | 5Gi | 256Mi / 1Gi |
| grafana | STS | grafana/grafana:13.2.0 | :3000 | 1Gi | 128Mi / 384Mi |
| mysqld- / redis- / mongodb- / kafka-exporter | Deploy ×4 | compose 와 같음 | :9104 / :9121 / :9216 / :9308 | — | 16Mi / 64Mi |
| pinpoint-hbase | Deploy(Recreate) + PVC | pinpointdocker/pinpoint-hbase:latest | :60000, :16010, :60020, :16030 | 5Gi | 1Gi / 2Gi |
| pinpoint-mysql | STS | mysql:8.0 | :3306 | 1Gi | 256Mi / 512Mi |
| pinpoint-redis | Deploy | redis:7.0.14 | :6379 | — | 32Mi / 128Mi |
| zoo1 | Deploy(Recreate) | zookeeper:3.4.13 | :2181 | — (emptyDir) | 128Mi / 256Mi |
| pinpoint-collector | Deploy | pinpointdocker/pinpoint-collector:latest | :9991–9996 TCP (+ `pinpoint-collector-udp` :9995/9996 UDP) | — | 512Mi / 1Gi |
| pinpoint-web | Deploy | pinpointdocker/pinpoint-web:latest | :8080, :9997 | — | 384Mi / 768Mi |

합계(인프라, Job 제외): 메모리 requests ≈ 10.6GiB, limits ≈ 22.9GiB, PVC 55.25GiB. `terminationGracePeriodSeconds: 60` — mysql·mongo·kafka·pinpoint-mysql·pinpoint-hbase.

compose 와 다른 점(이유는 각 매니페스트 주석):

- **enableServiceLinks: false**(redis-node·init Job 제외) — 같은 네임스페이스의 Service 마다 `<NAME>_PORT=tcp://…` env 가 들어가는데, cp-kafka 는 `KAFKA_PORT` 를 보고 죽고(“port is deprecated”), Spring(pinpoint)은 relaxed binding 으로 잘못 읽을 수 있다.
- **kafka** — 리스너는 `PLAINTEXT://kafka:9092` 하나(호스트용 `PLAINTEXT_INTERNAL://localhost:29092` 는 뺐다). 힙 `KAFKA_HEAP_OPTS` 를 limit 에 맞춰 줬다(zookeeper -Xmx256m, kafka -Xmx512m, debezium `HEAP_OPTS` -Xmx512M, zoo1 `JVMFLAGS` -Xmx128m) — compose 는 기본값(1G~2G)이었다.
- **redis 클러스터** — compose 의 고정 IP(10.90.0.11~16) 대신 노드마다 ClusterIP Service 를 두고 그 IP 를 `--cluster-announce-ip` 로 광고(파드가 재시작해도 nodes.conf 의 IP 가 맞는다). 클라이언트에는 호스트 이름 `redis-node-N` 을 광고. 클러스터 생성은 compose 의 redis-node-1 자체 부트스트랩 대신 Job `redis-cluster-init`(6노드 PONG → 슬롯 0 일 때만 create). **redis-node Service 를 지웠다 다시 만들면 ClusterIP 가 바뀌어 클러스터가 깨진다.**
- **mongo** — keyFile 은 Secret `mongo-keyfile` 을 init 컨테이너가 emptyDir 로 복사해 `chown 999:999 && chmod 400`. replica set 최초 구성: `kubectl -n modu exec mongo-01-0 -- bash /scripts/rs-init.sh`(ConfigMap `mongo-rs-init`).
- **rabbitmq** — 데이터가 노드 이름 `rabbit@rabbitmq` 에 묶여 있어(compose `hostname: rabbitmq`) `RABBITMQ_NODENAME=rabbit@rabbitmq` + `hostAliases`(rabbitmq → 127.0.0.1). StatefulSet 파드의 hostname 은 `rabbitmq-0` 으로 강제된다.
- **opensearch** — `ulimits memlock` 은 뺐다(memory_lock 을 안 켬). `vm.max_map_count` 는 노드 = Docker VM 커널 값 그대로(compose 의 opensearch 가 같은 커널에서 돌았다), sysctl init 컨테이너 없음.
- **prometheus** — 잡·대상 이름은 compose 의 `prometheus.yml` 그대로(ConfigMap `prometheus` 에 인라인. 대상이 이제 k8s Service). `node` 잡은 뺐고 `cadvisor` 잡은 kubelet cAdvisor(API 서버 프록시 `/api/v1/nodes/<node>/proxy/metrics/cadvisor`, ClusterRole `modu-prometheus`)로 바꿨다. 설정 바꾼 뒤 `kubectl -n modu exec prometheus-0 -- wget -qO- --post-data= http://localhost:9090/-/reload`.
- **grafana** — provisioning 을 projected 볼륨으로 compose 와 같은 디렉터리 모양으로. 대시보드 JSON 은 `base/observability/grafana/dashboards/`(이제 유일한 사본) → configMapGenerator 2개(client-side apply 의 last-applied 주석 256KiB 한도 때문에 나눔). `node-exporter.json`(468KB, 데이터도 없음)은 뺐다(git 이력에만 있다).
- **pinpoint** — batch·flink·quickstart·agent 는 compose 에서도 꺼져 있어 뺐다. ZooKeeper 는 `zoo1` 한 대(compose 는 zoo1..3) — HBase 의 `hbase-site.xml` 을 ConfigMap 으로 덮어 quorum 을 `zoo1` 로. **pinpoint-hbase 는 StatefulSet 이 아니라 Deployment + PVC**: HBase 는 자기 hostname 을 ZooKeeper 에 등록하는데 StatefulSet 은 hostname 을 `pinpoint-hbase-0`(아무도 못 푸는 이름)으로 강제한다 — Deployment 의 `hostname: pinpoint-hbase` = Service 이름. pinpoint-mysql 은 데이터 디렉터리가 비었을 때만 GitHub 에서 스키마를 받는다(compose 는 매 기동). 컬렉터 UDP 9995/9996 은 Service `pinpoint-collector-udp` 로 나눴다(같은 포트 번호 TCP+UDP 한 Service 는 client-side apply 가 패치를 못 만든다). 이미지 태그 `latest` 는 compose(.env `PINPOINT_VERSION=latest`) 그대로, `imagePullPolicy: IfNotPresent`.
- **Secret** — 비밀은 전부 `secretKeyRef`(Secret `infra`, 키 = compose 시절 .env 변수 이름, pinpoint 것만 `PINPOINT_` 접두사), 매니페스트에 값 없음. 원본은 한 파일 **`k8s/infra.env`**(gitignored, 23개 키 — 틀과 키마다 뜻은 `infra-secrets.example.env`)와 **`k8s/mongodb.key`**(gitignored). `./create-infra-secret.sh` 가 `infra.env` 를 읽어(source 하지 않고 KEY=VALUE 줄만) `infra` 를, `mongodb.key` 로 `mongo-keyfile` 을, `infra.env` 의 `MYSQL_ROOT_PASSWORD`·`COMMERCE_DB_PASSWORD` 로 `.my.cnf`(`[client]`·`[client.commerce]`, root)를 만들어 `mysqld-exporter` 를 만든다. 매니페스트·운영 스크립트가 쓰는 키가 빠지면 실패한다. 값은 화면에 안 찍는다. 운영 스크립트(`data/mysql/*.sh` 등)도 같은 Secret 을 `kubectl get secret infra -o jsonpath` 로 읽는다.

### 처음 옮길 때 순서

```bash
cd ~/workspace/modu_infra/k8s
# 0) compose 인프라를 내린다(같은 호스트 포트를 LoadBalancer 가 쓴다: 5601 3000 19090 9009 18080 9000 9001 15672 9200)
# 1) 예전 연결(selector 없는 headless Service + Endpoints 26개)을 지운다 — 같은 이름의 ClusterIP Service 로 바뀌는데
#    clusterIP 는 None → IP 로 바꿀 수 없다(apply 가 "RequireDualStack … not configured" 로 실패한다). 앱 파드는 잠시 인프라를 못 찾는다.
for s in mysql-member mysql-member-replica mysql-chat mysql-chat-replica mysql-push mysql-push-replica mysql-profile mysql-profile-replica \
         mysql-commerce mysql-commerce-replica redis redis-node-1 redis-node-2 redis-node-3 redis-node-4 redis-node-5 redis-node-6 \
         kafka zookeeper mongo-01 mongo-02 mongo-03 rabbitmq pinpoint-collector opensearch; do
  kubectl -n modu delete service/$s endpoints/$s --ignore-not-found
done
# 2) Secret + Ceph(위 '처음 한 번' 2·3)
./create-infra-secret.sh
kubectl apply --server-side -k ceph; sleep 5; kubectl apply --server-side -k ceph
# 3) 적용 — Service 가 워크로드보다 먼저 만들어진다(redis-node 의 service link env 에 필요)
kubectl apply -k overlays/dev
kubectl -n modu get pods -l app.kubernetes.io/component=data -w
kubectl -n modu logs job/redis-cluster-init        # "creating cluster" … 또는 "already formed"
kubectl -n modu exec redis-node-1-0 -- redis-cli cluster info | head -3
# 4) 빈 데이터로 시작했다면: mongo replica set, MySQL 복제, gh-ost 계정
kubectl -n modu exec mongo-01-0 -- bash /scripts/rs-init.sh
sh ../data/mysql/replica-setup.sh all            # 소스 → 레플리카 GTID 복제 + repl·읽기 계정
sh ../data/mysql/ghost-user-setup.sh             # gh-ost 계정 ghost
```

다시 만들기: `redis-cluster-init` 은 끝난 Job 이 그대로 남는다(pod 템플릿 불변). 클러스터를 새로 만들려면 `kubectl -n modu delete job redis-cluster-init` 뒤 `apply -k`.

### 데이터 이전(2026-10-03)

compose 볼륨의 데이터 디렉터리를 **통째로** PVC 에 복사했다(논리 덤프/복원이 아님). 그래서 MySQL 의 GTID 복제 상태·계정·`SET PERSIST`(레플리카 `super_read_only`), Mongo 복제셋 설정, Kafka 토픽·오프셋이 그대로 이어졌다. 복사 도구는 "PVC 를 만들고 busybox 파드에 마운트 → `docker run … tar c | kubectl exec -i … tar x` → chown" 한 번이면 된다.

| 대상 | 방법 | 결과 |
|---|---|---|
| Grafana | 볼륨 복사(uid 472) | 대시보드 6개·데이터소스 유지 |
| OpenSearch·Prometheus·Pinpoint(HBase·MySQL) | 새로 시작 (이력 버림 — 결정) | 로그는 새 인덱스로 바로 유입, Prometheus 대상 24개 up |
| ZooKeeper(data+log)·Kafka | 볼륨 복사 | 토픽 8개·오프셋 유지 |
| Redis·Redis 클러스터·RabbitMQ | 새로 시작 (캐시·세션 — 결정) | 클러스터는 `redis-cluster-init` Job 이 생성(16384 슬롯). 사용자는 한 번 다시 로그인 |
| MongoDB ×3 | 볼륨 복사(uid 999) | PRIMARY + SECONDARY 2, `modu-chat.chat` 105건 그대로 |
| MinIO | 호스트 디렉터리 복사(uid 1000) | 19MB | (2026-10-05 에 다시 Ceph RGW 로 옮김 — 아래 "Ceph")
| MySQL 5쌍 | compose 정지 → 소스·레플리카 볼륨 복사(uid 999) → k8s 기동 | 쌍마다 행 수 일치, 레플리카 IO/SQL Yes(소스가 늦게 뜨면 60초 뒤 재시도로 붙는다), `super_read_only=1` |

순서는 관측 → Kafka/Redis/RabbitMQ → Mongo/MinIO → MySQL. 앱은 그대로 둔 채 인프라 Service 를 compose용(headless+Endpoints)에서 k8s 것으로 바꿔 끼웠고, 해당 인프라를 쓰는 서비스만 한 번씩 재시작했다. Flip3 로 채팅 전송(k8s MySQL 소스·레플리카에 저장)·푸시 수신까지 확인.

**옮기면서 밟은 것 (다음에 또 겪지 않게)**
- **노드 디스크 100%**: Docker VM 디스크(117GB)가 가득 차 Mongo 가 WiredTiger `error 28`(ENOSPC)로 기동 실패했다. 빌드 캐시·안 쓰는 이미지·멈춘 컨테이너를 지워 59GB 를 비웠다. 복사 전에 `docker exec desktop-control-plane df -h /` 를 본다.
- **LoadBalancer 호스트 포트 증발**: compose 앱 컨테이너(8000·8888·15672 를 쓰던)를 `docker compose rm` 하자 Docker Desktop 이 같은 포트의 k8s LB 포워딩까지 걷어 갔다. LB Service 를 지워 다시 만들려 하면 `service.kubernetes.io/load-balancer-cleanup` finalizer 에 걸려 멈춘다 → `kubectl patch svc <lb> -p '{"metadata":{"finalizers":null}}' --type=merge` 뒤 다시 apply. 안 지우고 annotation 만 바꿔도(`kubectl annotate svc <lb> modu/lb-nudge=$(date +%s) --overwrite`) 포워딩이 다시 생긴다.
- **Mongo "not a member"**: Service 를 헤드리스 + `publishNotReadyAddresses: true` 로(위 표 참고).
- **HBase RegionServer 포트**: 이미지는 16020 에 뜬다(60020 아님). readiness 가 틀리면 pinpoint-collector·web 이 `Connection refused` 로 CrashLoop.
- **Pinpoint 에이전트 컬렉터 주소**: `-D` 로는 안 바뀐다 — init 컨테이너에서 설정 파일을 고친다.
- **compose 쪽 컨테이너 IP 가 바뀌면** headless Endpoints 가 어긋나 앱이 멈춘 것처럼 보였다(이제 compose 가 없으니 해당 없음).
- **13개 JVM 템플릿을 한꺼번에 바꾸지 말 것** — 위 "롤아웃은 한 번에 하나씩".
- **NetworkPolicy 는 쓰지 말 것(Docker Desktop)**: kindnet 이 NetworkPolicy 를 nftables queue 로 강제하는데(`nft list table inet kindnet-network-policies`) verdict 가 `netlink send: i/o timeout` 으로 실패하면 **정책에 걸린 파드로 가는 파드→파드 패킷이 전부 버려진다**(노드→NodePort 만 됨). 2026-10-04 Argo CD 설치 직후 UI 8090 이 먹통이 된 원인 — 공식 매니페스트의 NetworkPolicy 7개를 `cicd/argocd/kustomization.yaml` 에서 지운다. 증상이 또 나오면 `kubectl get networkpolicy -A` 로 정책이 있는지부터 본다.

## Pinpoint 켜기/끄기

dev 는 꺼져 있다(스택 6개 replicas 0, JVM 에이전트 패치 주석). PVC(`pinpoint-hbase-data`, `pinpoint-mysql`)는 남아 있어 켜면 이전 데이터가 이어진다. 켜고 끄는 건 매니페스트 두 군데(`overlays/dev/kustomization.yaml`)다.

1. `replicas:` 의 Pinpoint 6개(zoo1·pinpoint-hbase·pinpoint-mysql·pinpoint-redis·pinpoint-collector·pinpoint-web)를 `1`(끌 때 `0`)로.
2. `patches:` 블록(에이전트 2개)의 주석을 푼다(끌 때 주석).
3. **JVM 13개 템플릿이 한꺼번에 바뀌므로** 반드시 "롤아웃은 한 번에 하나씩" 절차로: 13개 `rollout pause` → `kubectl apply -k overlays/dev` → 하나씩 `rollout resume` + `rollout status`. 켤 때는 먼저 스택이 뜨길 기다린다(`pinpoint-hbase` Ready → collector·web Ready; HBase 가 3~5분 걸린다). 끌 때 순서는 반대여도 상관없다(에이전트는 컬렉터가 없어도 돌지만 종료가 20초 늦어진다).
4. 켠 뒤 확인: `http://localhost:18080` 앱 목록에 13개, 끈 뒤 확인: `kubectl -n modu get deploy -o json | grep -c pinpoint-bootstrap` 가 0.

2026-10-04 끄기 결과: 파드 19개 → 13개 JVM 재시작(한 번에 하나씩, 약 8분), Pinpoint 6개 종료. 로그 수집기의 Pinpoint 에이전트 잡음 필터(`otel-collector.yaml` `drop_noise`)는 그대로 둔다(켜도 조용하게).

## Ceph (S3 오브젝트 스토리지, 2026-10-05 부터 — MinIO 대체)

MinIO 는 공식 이미지·바이너리 배포가 막혀(노드에 수동 import 해 쓰던 상태) **Rook-Ceph** 의 RGW(S3 게이트웨이)로 바꿨다. 매니페스트는 `k8s/ceph/`(네임스페이스 `rook-ceph`, Rook v1.20.8, Ceph v20.2.4), Argo Application `modu-ceph`.

```bash
kubectl apply --server-side -k k8s/ceph        # 처음 한 번(CRD 가 커서 server-side; CRD 뒤에 CephCluster 가 들어가므로 두 번 돌린다)
kubectl -n rook-ceph get cephcluster modu      # PHASE Ready, HEALTH HEALTH_OK (처음엔 이미지 2개(≈2GB) 받느라 5~10분)
kubectl -n rook-ceph get cephobjectstore modu  # PHASE Ready → RGW
kubectl -n rook-ceph get secret rook-ceph-object-user-modu-storage-service -o jsonpath='{.data.AccessKey}' | base64 -d   # storage-service 키(SecretKey 도)
```

| 구성 | 내용 |
|---|---|
| 디스크 | 노드엔 빈 블록 디바이스가 없어서 `loop-disk` DaemonSet(privileged)이 `/var/lib/modu-ceph/osd0.img`(10GiB sparse)를 `/dev/loop7` 로 붙인다. Docker Desktop 재시작 때 loop 는 사라지고 DaemonSet 이 다시 붙인다(파일은 남아 데이터 유지). operator 설정 `ROOK_CEPH_ALLOW_LOOP_DEVICES=true` |
| 클러스터 | MON 1, MGR 1(대시보드 http://localhost:7001(7000 은 macOS AirPlay 가 점유), admin / Secret `rook-ceph-dashboard-password`), OSD 1, 복제 없음(`osd_pool_default_size 1`, 풀 size 1). crash collector·log collector·exporter 끔, CSI 드라이버 끔(볼륨은 local-path 그대로) |
| RGW | `CephObjectStore modu`(instances 1, 포트 80) → Service `rook-ceph-rgw-modu.rook-ceph.svc`. 앱은 modu 네임스페이스의 ExternalName Service **`rgw`**(`base/data/rgw.yaml`)로 본다 → storage-service `s3.endpoint: http://rgw:80`. Mac 에선 LB **7480** |
| 사용자 | `CephObjectStoreUser storage-service` → Secret `rook-ceph-object-user-modu-storage-service`(AccessKey·SecretKey). 값은 config-repo `storage-service.yml` 의 `s3.accessKey/secretKey` 에 `{cipher}` 로 |
| 메모리 | limits 합 ≈ 3.5GiB(mon 512Mi, mgr 512Mi, osd 1.5Gi — 1.2GiB 미만이면 osd_memory_target 하한(896MB) 때문에 기동 assert, rgw 512Mi, operator 256Mi, csi 컨트롤러 소량, prepare 512Mi 일시) |

- **밟은 것(2026-10-05 설치 때)**: ① Rook 1.20 은 CSI 를 안 써도 `csi-operator.yaml`(csi.ceph.io CRD `CephConnection` + 컨트롤러)이 있어야 클러스터를 만든다. CSI 드라이버는 operator.yaml 안의 `Driver` CR 2개를 kustomize 로 지워서 끈다(옛 `ROOK_CSI_ENABLE_*` 키는 무시됨; rbd 노드플러그인은 Docker Desktop 커널에서 CrashLoop). ② 예제의 `security.cephx.csi.keyType: aes` 는 Ceph v20 이 거부(`get-or-create-key … exit status 22`) — 빼면 기본값으로 된다. ③ `cephConfig.global.osd_memory_target` 은 설정 실패 — Rook 이 OSD limit 에서 계산하므로 적지 않는다. ④ 노드에 udevd 가 없어 ceph-volume 이 `No udev data could be retrieved for /sys/block/…` 로 모든 디바이스를 건너뛴다 — `loop-disk` DaemonSet 이 `/run/udev/data/b<maj>:<min>` 을 모든 블록 디바이스·파티션(nbd·vda1 포함)에 대해 써 준다. ⑤ OSD limit 1Gi 면 `osd_memory_target`(limit×0.8) 이 하한 896MB 미만이라 ceph-osd 가 assert 로 죽는다 → 1.5Gi. ⑥ OSD prepare 를 다시 돌리려면 prepare Job 을 지우고 operator 를 재시작한다(annotation 으론 안 움직임).
- **데이터 이전(2026-10-05)**: rclone 일회성 파드(`kubectl run … --image=rclone/rclone --command -- sh -c 'rclone copy --metadata src:file-storage dst:file-storage'`, S3 provider Minio→Ceph)로 MinIO `file-storage` → RGW 같은 버킷(메타데이터 포함). 결과: 51개 객체 18.6MiB, 양쪽 크기 일치. 뒤에 MinIO(StatefulSet·Service·LB·PVC·Secret 키·노드에 import 한 이미지)는 지웠다. 옮기기 전 백업: `~/modu-data/backup/2026-10-03-k8s/minio`.
- **운영에선** loop 파일 대신 노드 디스크(`storage.devices`), MON 3·size 3, `priorityClassNames` 그대로. 매니페스트에서 바뀌는 건 그 줄들뿐이다.
- Argo 는 CRD 를 server-side 로 적용한다(cephclusters CRD 가 300KB 라 client-side 한도 초과) — CRD 에 `argocd.argoproj.io/sync-options: ServerSideApply=true`. `CephCluster.spec.storage.nodes` 는 Rook 이 채우므로 비교 제외.

## Argo CD 로 배포 (2026-10-04 부터)

dev 의 배포 주체는 **Argo CD**(`k8s/cicd/argocd`, 네임스페이스 `argocd`, v3.5.3)다. Git 이 진실이고 Argo 가 그걸 클러스터에 맞춘다. 모두의 시스템의 "배포 버튼"은 이 위에 얹는다(태그 커밋 + Sync 호출 — 후속).

```bash
kubectl apply --server-side -k k8s/cicd/argocd          # 처음 한 번(CRD 가 커서 server-side). Application 이 CRD 보다 먼저라 두 번 돌린다.
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d   # UI http://localhost:8090, 사용자 admin
```

| Application | 소스 | 대상 | 내용 |
|---|---|---|---|
| `modu-dev` | modu_infra `main` `k8s/overlays/dev` | `modu` | 앱 17 + 인프라 전부(객체 144개) |
| `modu-config-repo` | modu_platform `develop` 루트 `kustomization.yaml` | `modu` | config-repo ConfigMap 3개 |

- **수동 Sync(버튼)**. 머지해도 자동으로 적용되지 않는다 — UI 의 Sync 또는 API(`POST /api/v1/applications/<app>/sync`). Argo 의 self-heal(손으로 바꾼 걸 Git 으로 되돌림)은 자동 동기화의 하위 옵션이라 수동 모드엔 없다. `kubectl` 로 바꾸면 UI 에 OutOfSync 로 보인다.
- **prune 없음**. Git 에서 지운 객체는 자동으로 안 지운다(UI 에서 확인 후 Sync 창의 Prune 체크).
- **sync-wave**: JVM Deployment 13개는 base 의 annotation `argocd.argoproj.io/sync-wave` 1(config)…13(commerce). Argo 는 앞 wave 가 Healthy 가 돼야 다음을 적용하므로 공통 패치를 바꿔도 한 번에 하나씩 롤아웃된다(JVM 26개 OOM 사고 재발 방지). 인프라·nginx 는 0(기본, 가장 먼저).
- **Argo 가 안 건드리는 것**: Secret 4개(`config-service`·`infra`·`mongo-keyfile`·`mysqld-exporter` — Git 에 없음, `create-infra-secret.sh`), Argo 자신. 추적은 annotation `argocd.argoproj.io/tracking-id`(라벨 방식 아님).
- **ApplyOutOfSyncOnly**: 바뀐 객체만 apply. 완료된 Job(`redis-cluster-init`)은 `spec` 비교 제외.
- 뺀 컴포넌트: dex(SSO)·notifications·applicationset 은 replicas 0. 메모리 limits 합 ≈ 1.1GiB(Pinpoint 를 끄며 비운 자리).

**배포 절차**: 모두 시스템 콘솔(http://localhost:8084) → **배포** 탭 → 서비스 행의 [배포] → CI 가 올린 태그(`develop-<sha7>`, 커밋 메시지·시각 표시) 선택 → 배포. 뒤에서 `deploy-service`(modu_platform, `base/platform/deploy-service.yaml`)가 ① `overlays/dev/kustomization.yaml` 의 `images[].newTag` 를 GitHub API 로 main 에 커밋 → ② Argo CD 계정 `deploy`(role:deployer, 이 저장소 `cicd/argocd` 의 argocd-cm/argocd-rbac-cm 패치)로 그 Deployment 만 Sync → ③ 롤아웃을 지켜보며 진행률(커밋 20% → 동기화 50% → 파드 준비 100%)을 돌려준다. 롤백은 같은 탭의 [롤백](직전 성공 태그). 손으로 할 때는 예전처럼 태그 PR → 머지 → Argo UI Sync.
토큰 둘(GitHub contents:write+read:packages, Argo deploy 계정 API 키)은 modu_platform `config-repo/deploy-service.yml` 에 `{cipher}` 로 있다. Argo 토큰 재발급: admin 으로 `POST /api/v1/account/deploy/token` → 다시 암호화.

2026-10-04 도입 때: 기존 객체 144개를 그대로 "입양"(첫 Sync 는 tracking annotation 과 sync-wave annotation 만 추가, 파드 재시작 0). 도입 PR 머지 전까지 두 Application 의 `targetRevision` 을 feature 브랜치로 바꿔 두었다가(main 에는 아직 `config-repo-configmaps.yaml` 참조가 있어 빌드가 안 됨) 머지 후 매니페스트대로(`main`/`develop`) 되돌린다.

## config-repo 바꿀 때

config-repo 의 ConfigMap 3개(`config-repo-root`·`-messenger`·`-commerce`)는 2026-10-04 부터 이 저장소가 아니라 **modu_platform 루트의 `kustomization.yaml`**(configMapGenerator, 해시 접미사 없음)이 만들고, Argo CD Application `modu-config-repo` 가 적용한다(아래 "Argo CD 로 배포"). dev 오버레이에는 없다.

```bash
# modu_platform 에서 config-repo 를 고치고(새 파일이면 kustomization.yaml files 에도 추가 — ./k8s-check.sh 가 잡는다) develop 에 머지
# → Argo UI(http://localhost:8090) 에서 modu-config-repo Sync   (Argo 없이: kubectl apply -k ~/workspace/modu_platform)
kubectl -n modu rollout restart deploy/config-service
# 설정을 받아 가는 서비스도 다시 띄워야 반영된다(Spring Cloud Bus /busrefresh 연동은 후속)
kubectl -n modu rollout restart deploy/<svc>
```

스크립트는 `password`·`token`·`key` 같은 키에 `{cipher}` 가 아닌 값이 있으면 실패한다(평문 비밀이 ConfigMap 으로 새는 것을 막는다).

## 이미지 태그 바꾸기(배포)

CI(`.github/workflows/images.yml`)가 GHCR 에 올린 태그를 `overlays/dev/kustomization.yaml` 의 `images[].newTag` 에 적고 apply 하면 그 Deployment 만 롤링된다.

```bash
# 한 서비스만 빠르게
kubectl -n modu set image deploy/member-service member-service=ghcr.io/tear94fall/modu-chat/member-service:<tag>
kubectl -n modu rollout status deploy/member-service
# 같은 태그(develop)로 다시 받기: IfNotPresent 라 노드에 이미 있으면 안 받는다 → docker pull 로 먼저 받고 restart
docker pull ghcr.io/tear94fall/modu-chat/member-service:develop
kubectl -n modu rollout restart deploy/member-service
# 되돌리기
kubectl -n modu rollout undo deploy/member-service
kubectl -n modu rollout history deploy/member-service
```

## 자주 쓰는 명령

```bash
kubectl -n modu get pods -o wide
kubectl -n modu logs -f deploy/chat-service               # stdout JSON 한 줄(logstash encoder) 그대로
kubectl -n modu describe pod -l app=config-service          # probe 실패·CreateContainerConfigError 원인
kubectl -n modu exec deploy/auth-service -- curl -s mysql-member:3306 | head -c 20   # 인프라 연결 확인
kubectl -n modu get sts,pvc                                 # 인프라 StatefulSet·볼륨
kubectl -n modu exec -it mysql-member-0 -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'
kubectl delete -k overlays/dev                              # 전부 내리기 — StatefulSet 의 PVC 는 남는다(PVC 를 지우면 데이터도 지워진다: reclaim Delete).
                                                            # Secret 도 남는다: kubectl -n modu delete secret config-service infra mongo-keyfile mysqld-exporter
```

## k8s 에 없는 것 (후속)

- **gh-ost 이미지** — `modu-gh-ost:1.1.11` 은 레지스트리에 없어 `data/mysql/gh-ost/build-and-import.sh` 로 노드의 containerd 에 넣는다(MinIO 이미지와 같은 방식). 노드를 다시 만들면 다시. 실제 클러스터에선 GHCR 에 올리고 `imagePullPolicy` 를 바꾼다.
- **node-exporter·cadvisor** — 도커 호스트 지표라 옮기지 않았다. 컨테이너 지표는 Prometheus 가 kubelet cAdvisor 로 긁는다(라벨이 달라 Grafana `cadvisor` 대시보드는 `pod`/`container` 라벨로 고쳐야 한다). `node-exporter.json` 대시보드는 뺐다.
- **앱 파드의 service link env** — 인프라 Service 가 ClusterIP 가 되면서 앱 파드에도 `MYSQL_MEMBER_PORT=tcp://…`, `KAFKA_PORT` 같은 env 가 수십 개 들어간다. 겹치는 이름은 지금 없지만 앱 Deployment 에도 `enableServiceLinks: false` 를 주는 것이 안전하다.
- **Pinpoint 요청 추적** — (dev 에선 꺼 둠) 켰을 때 에이전트 13개가 컬렉터에 등록되고 앱 목록에 보이지만, 요청 처리 로그 줄에 `PtxId`/`PspanId` 가 아직 안 붙는다(기동 줄에는 붙음). 운영에 올리기 전에 트랜잭션 샘플링/서블릿 플러그인 설정 확인 필요.
- **Prometheus 스크레이프** — 정적 대상(Service 이름)만. 파드가 2개 이상인 Deployment 는 Service 로 긁으면 매번 다른 파드가 응답한다 — 그때는 kubernetes_sd(role: endpoints/pod)로 바꿀 것.
- **Ingress** — 안 쓴다. Docker Desktop 에선 LoadBalancer Service 로 충분. 실제 클러스터로 갈 때 Ingress(게이트웨이만 노출)로.
- **runAsNonRoot** — 이미지에 USER 가 없어 false. Dockerfile 에 비 root 사용자 추가 후 true 로.
- **storage-service `/data`** — compose 는 bind mount, k8s 는 emptyDir(multipart 임시 파일이라 유실돼도 된다; 실제 파일은 Ceph RGW).
- **config-service·gateway replicas** — dev 는 메모리 때문에 1. 실제 클러스터에선 2 이상.
- **백업** — PVC 는 local-path(노드 디스크, reclaim Delete). 주기적 `mysqldump`/`mongodump` 를 CronJob 으로 두는 것이 다음 할 일. 옮기기 직전 백업은 `~/modu-data/backup/2026-10-03-k8s/`.
