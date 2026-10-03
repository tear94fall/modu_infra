# k8s — 앱 계층 Kustomize 매니페스트

modu 의 **앱 계층**(플랫폼 2 + 메신저 10 + 커머스 2 + 콘솔 3 = Deployment 17개)을 로컬 Docker Desktop Kubernetes(context `docker-desktop`, 1 노드)에 띄우는 매니페스트입니다.
**상태 있는 인프라**(MySQL×10, Redis, Redis 클러스터×6, Kafka, ZooKeeper, Mongo×3, MinIO, RabbitMQ, OpenSearch, Pinpoint)는 같은 Mac 의 docker compose(`data/`, `monitoring/`, `pinpoint-docker/`)에 그대로 두고, 파드가 compose 때와 **같은 호스트 이름**(`mysql-chat`, `kafka`, `redis-node-1` …)으로 찾도록 컨테이너 IP 를 selector 없는 headless Service + Endpoints 로 이어 줍니다.

```
k8s/
  base/                              # 환경 공통. namespace modu, 공통 라벨 app.kubernetes.io/part-of=modu
    namespace.yaml
    platform/   config-service.yaml gateway-service.yaml           # replicas 2
    messenger/  auth member chat chat-store ws push storage profile point schedule (-service.yaml)
    commerce/   commerce-service.yaml web.yaml
    admin/      modu-admin.yaml modu-system.yaml modu-internal.yaml
  overlays/dev/
    kustomization.yaml               # images(태그), replicas, 아래 생성 파일들
    gen-infra-endpoints.sh           # docker inspect → infra-endpoints.yaml (headless Service + Endpoints)
    gen-config-repo-configmaps.sh    # modu_platform/config-repo → config-repo-configmaps.yaml (ConfigMap 3개)
    loadbalancers.yaml               # Mac 에서 들어오는 입구: LoadBalancer 6개(compose 와 같은 호스트 포트)
    otel-collector.yaml              # 파드 로그 → OpenSearch modu-app-logs (DaemonSet)
    pinpoint-agent-patch*.yaml       # JVM Deployment 에 Pinpoint 에이전트(init 컨테이너 + JDK_JAVA_OPTIONS)
    secret.example.yaml              # Secret config-service 의 틀(값 비어 있음) — kustomization 에 없음
```

## dev 의 기본 실행 환경 (2026-10-03 부터)

dev 의 앱 계층은 **k8s 에서 돈다.** compose 의 앱 스택(modu_platform, modu_messenger, modu_commerce, modu_admin)은 내려 두고, 인프라(`data/`, `monitoring/`, `pinpoint-docker/`)만 compose 로 띄운다. 둘을 같이 띄울 메모리가 없다(Docker VM 24GB).

- **입구**: Docker Desktop 의 k8s 는 NodePort 를 localhost 로 내보내지 않지만 **LoadBalancer Service 는 Mac 의 모든 인터페이스(*:포트)로 연다.** compose 가 쓰던 포트 그대로라 앱·콘솔·웹 주소가 안 바뀐다 — 게이트웨이 8000(안드로이드는 `192.168.0.3:8000`), 콘솔 8081/8084/8085, 커머스 웹 8082, config-service 8888(dev 도구용).
- **로그**: `otel-collector` DaemonSet 이 `/var/log/pods/modu_*` 를 읽어 compose 와 같은 OpenSearch 인덱스 `modu-app-logs` 로 보낸다(`attributes.project: k8s`, `attributes.container`).
- **Pinpoint**: JVM 13개에 에이전트(컬렉터와 같은 3.1.0). 에이전트 3.1 은 `-D` 로 설정을 덮어쓸 때 `pinpoint.` 접두사가 필요하다.
- **롤아웃은 한 번에 하나씩.** 단일 노드·빠듯한 메모리에서 13개 Deployment 의 pod 템플릿을 한꺼번에 바꾸면(공통 패치 수정 + `apply -k`) maxSurge 1 때문에 JVM 이 26개가 되어 노드가 멈춘다(2026-10-03 실제로 API 서버가 응답 불능). 공통 변경은:
  ```bash
  J=(config-service gateway-service auth-service member-service chat-service chat-store-service ws-service push-service profile-service storage-service point-service schedule-service commerce-service)
  kubectl -n modu rollout pause deploy "${J[@]}"      # zsh 는 $J 를 단어로 안 나눈다 — 배열로
  kubectl apply -k overlays/dev
  for d in "${J[@]}"; do kubectl -n modu rollout resume deploy/$d; kubectl -n modu rollout status deploy/$d; done
  ```
  이미지 태그 하나만 바꾸는 평소 배포는 그 Deployment 하나만 굴러가므로 그냥 `apply -k` 하면 된다.
- **compose 로 되돌리기**: `kubectl -n modu scale deploy --all --replicas=0` 뒤 각 앱 스택에서 `docker compose up -d`.

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

# 2) compose 인프라가 떠 있는 상태에서 생성 파일 두 개
overlays/dev/gen-infra-endpoints.sh          # 컨테이너가 하나라도 없으면 실패한다
overlays/dev/gen-config-repo-configmaps.sh   # ~/workspace/modu_platform/config-repo (CONFIG_REPO 로 바꿀 수 있다)

# 3) 확인 후 적용
kubectl kustomize overlays/dev > /dev/null
kubectl apply --dry-run=client -k overlays/dev
kubectl apply -k overlays/dev
kubectl -n modu rollout status deploy/config-service --timeout=5m   # 나머지는 config 가 뜰 때까지 fail-fast 로 재시작하다가 따라 올라온다
kubectl -n modu rollout status deploy --timeout=10m
kubectl -n modu get pods -o wide
```

`kubectl apply -k` 를 한 번에 돌려도 된다. 서비스는 config-service 를 못 만나면 기동에 실패(`spring.cloud.config.fail-fast`)하고 CrashLoopBackOff 로 재시도하므로 config 가 뜨면 자연히 따라온다. Secret 이 없으면 config-service 파드가 `CreateContainerConfigError` 로 기다리다 Secret 이 생기면 바로 뜬다.

메모리 requests 합은 약 7.1GiB(JVM 14개×512Mi + nginx 4개×16Mi; 노드 allocatable 은 `kubectl describe node docker-desktop | grep -A5 Allocatable`). 모자라면 Pending 이 되니 Docker Desktop 의 메모리를 올리거나 오버레이 `replicas:` 를 줄인다.

## 포트 — Mac 에서 들어오는 길

`overlays/dev/loadbalancers.yaml` 의 LoadBalancer Service 가 Mac 의 모든 인터페이스에 compose 와 **같은 포트**로 열린다(Docker Desktop 은 NodePort 는 localhost 로 안 내보낸다). 안드로이드 기기는 Mac 의 LAN IP(`192.168.0.3`).

| URL | 대상 |
|---|---|
| http://localhost:8000 | gateway-service (앱 API, `/auth-service/**`, `/member-service/**` …) |
| http://localhost:8082 | modu-commerce-web (nginx → gateway) |
| http://localhost:8081 / 8084 / 8085 | modu-admin / modu-system / modu-internal 콘솔 |
| http://localhost:8888 | config-service (dev 도구용 — 토큰 발급 스크립트 등) |

개별 서비스 포트(9900, 8080 …)는 바깥에 열지 않는다. 필요하면 `kubectl -n modu port-forward svc/member-service 8080:8080`.

## 인프라 연결 (infra-endpoints.yaml)

`gen-infra-endpoints.sh` 가 각 컨테이너의 IP 를 `docker inspect` 로 읽어 headless Service(`clusterIP: None`, selector 없음) + 같은 이름의 Endpoints 를 쓴다. 파드는 `mysql-chat:3306` 처럼 compose 와 같은 이름으로 붙는다.

| 이름 | 네트워크 | 포트 |
|---|---|---|
| mysql-{member,chat,push,profile,commerce} + `-replica` | modu-infra | 3306 |
| redis | modu-infra | 6379 |
| redis-node-1..6 | modu-data_redis-cluster (고정 10.90.0.11..16 — 클러스터가 이 IP 를 광고한다) | 6379 |
| kafka / zookeeper | modu-infra | 9092 / 2181 |
| mongo-01..03 | modu-infra | 27017 |
| minio / rabbitmq | modu-infra | 9000 / 5672 |
| pinpoint-collector | pinpoint-docker_pinpoint | 9991, 9992, 9993 |

- 파드 → 도커 브리지 IP 는 **컨테이너가 publish 한 포트만** 통과한다(도커 방화벽). 위 포트는 모두 publish 돼 있다(kafka 9092, redis-node 6379 는 이 용도로 localhost 에 열어 둔 것).
- 컨테이너를 다시 만들어 IP 가 바뀌면(`docker compose up -d` 로 재생성) 스크립트를 다시 돌리고 `kubectl apply -k overlays/dev`. 파드는 DNS 로 매번 풀므로 재시작 없이 따라간다(JDBC 풀의 기존 연결은 끊긴 뒤 새로 맺는다).
- 컨테이너가 없거나 네트워크에 안 붙어 있으면 스크립트가 바로 실패하고 기존 파일을 남긴다.
- k8s 1.33+ 는 `v1 Endpoints` 에 deprecation 경고를 낸다(EndpointSlice 권장). 동작은 같고 selector 없는 Service 의 Endpoints 는 자동으로 EndpointSlice 로 미러링된다. 경고가 거슬리면 스크립트의 Endpoints 블록을 `discovery.k8s.io/v1 EndpointSlice` 로 바꾸면 된다.

## config-repo 바꿀 때

```bash
overlays/dev/gen-config-repo-configmaps.sh
kubectl apply -k overlays/dev
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
kubectl -n modu exec deploy/auth-service -- curl -s mysql-member:3306 | head -c 20   # 인프라 Endpoints 연결 확인
kubectl -n modu get endpoints                               # 인프라 IP 가 compose 와 같은지
kubectl delete -k overlays/dev                              # 전부 내리기(Secret 은 남는다: kubectl -n modu delete secret config-service)
```

## k8s 에 없는 것 (후속)

- **상태 있는 인프라 전부** — compose 그대로. 이 매니페스트는 앱 계층 + 연결만.
- **Pinpoint 에이전트** — compose 는 `pinpoint-agent` 볼륨을 마운트하고 `*_AGENT_OPTS` 로 `-javaagent` 를 넣었다. k8s 는 넣지 않았다(에이전트 jar 를 initContainer 로 받아 emptyDir 에 넣고 `JAVA_TOOL_OPTIONS` 에 `-javaagent` 추가 필요). `JAVA_TOOL_OPTIONS=-Dprofiler.logback.logging.transactioninfo=true` 만 남겨 둬 에이전트를 붙이면 바로 MDC 가 이어진다. `pinpoint-collector` Endpoints 는 그때를 위해 미리 있다.
- **로그 수집** — monitoring 의 OTel Collector 는 도커 json-file(`/var/lib/docker/containers`)만 읽는다. **k8s 파드 로그는 아직 OpenSearch 로 가지 않는다**(`kubectl logs` 만). 같은 Collector 설정을 DaemonSet 로 옮기고 경로를 `/var/log/pods` 로 바꾸면 된다(README 로그 절).
- **Prometheus 스크레이프** — monitoring 의 Prometheus 는 compose 컨테이너 이름을 대상으로 한다. 파드는 대상이 아니다(kubernetes_sd 또는 NodePort 추가 필요).
- **Ingress** — 안 쓴다. NodePort 로 충분(Docker Desktop 이 localhost 로 매핑).
- **runAsNonRoot** — 이미지에 USER 가 없어 false. Dockerfile 에 비 root 사용자 추가 후 true 로.
- **storage-service `/data`** — compose 는 `/var/modu-chat/storage/data` bind mount, k8s 는 emptyDir(multipart 임시 파일이라 유실돼도 된다; 실제 파일은 MinIO).
- **storage-service·ws-service 의 `spring.datasource.url`(compose)** — 두 서비스는 JPA 의존이 없고 `mysql` 호스트도 없는 죽은 설정이라 옮기지 않았다(compose 에서도 지울 것).
- **commerce-service 의 `JAVA_TOOL_OPTIONS`** — compose 에 없어 안 넣었다(Pinpoint 를 붙일 때 같이).
