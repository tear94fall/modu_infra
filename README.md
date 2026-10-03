# modu_infra

modu 프로젝트(modu_messenger, modu_commerce)가 같이 쓰는 인프라와 관측성 스택입니다.
각 프로젝트의 `backend/docker-compose.yml` 에는 애플리케이션 서비스만 있고, 인프라는 여기서 먼저 띄웁니다.

이 저장소 옆에 다음 두 저장소가 clone 되어 있다고 가정합니다.

- modu_messenger — https://github.com/tear94fall/modu_chat (경로: `../modu_chat`)
- modu_commerce — https://github.com/tear94fall/modu_commerce (경로: `../modu_commerce`)

## 구성 (2026-10-03 부터 전부 k8s)

dev 환경은 **앱도 인프라도 Docker Desktop Kubernetes(context `docker-desktop`, 네임스페이스 `modu`)** 에서 돈다. 매니페스트와 운영 절차는 [`k8s/README.md`](k8s/README.md).

| 디렉터리 | 내용 |
|---|---|
| `k8s/` | Kustomize 매니페스트 — `base/{platform,messenger,commerce,admin}` 앱 17개, `base/data`(MySQL 10, Redis, Redis 클러스터 6, ZooKeeper·Kafka·Debezium·kafka-ui, Mongo 3, MinIO, RabbitMQ), `base/observability`(OpenSearch·Dashboards, Prometheus·Grafana·exporter, Pinpoint, OTel Collector), `overlays/dev` |
| `data/`, `monitoring/`, `pinpoint-docker/` | **예전 compose 구성(참고용).** 2026-10-03 에 k8s 로 옮기고 컨테이너·볼륨·네트워크는 지웠다. k8s 매니페스트의 원본 설정(명령·환경변수·헬스체크)을 찾아볼 때 본다 |
| `data/mysql/` | 스키마 기준선·변경 이력·gh-ost·DBA 절차 — 여전히 유효(아래 "스키마 관리") |

## 최초 준비 / 기동

```bash
kubectl config use-context docker-desktop
cd k8s
kubectl apply -f base/namespace.yaml
kubectl -n modu create secret generic config-service --from-literal=ENCRYPT_KEY=… --from-literal=INTERNAL_API_TOKEN=…   # modu_platform/.env 의 값
./create-infra-secret.sh                      # data/.env, monitoring/.env, pinpoint-docker/.env 의 값으로 Secret infra·mongo-keyfile·mysqld-exporter
overlays/dev/gen-config-repo-configmaps.sh    # modu_platform/config-repo → ConfigMap
docker save quay.io/minio/minio:RELEASE.2024-02-14T21-36-02Z | docker exec -i desktop-control-plane ctr -n k8s.io images import -   # MinIO 이미지는 공개 저장소에서 더 못 받는다
kubectl apply -k overlays/dev
```

Mac 에서 들어가는 포트(LoadBalancer): 게이트웨이 8000 · 콘솔 8081/8084/8085 · 커머스 웹 8082 · config 8888 · OpenSearch Dashboards 5601 · Grafana 3000 · Prometheus 19090 · Pinpoint 18080 · kafka-ui 9009 · MinIO 9000/9001 · RabbitMQ 15672. DB·Kafka·Redis 는 밖에 열지 않는다(`kubectl port-forward`).

## 로그

서비스는 로그를 **stdout 에 한 줄 JSON**(logstash-logback-encoder)으로만 씁니다. `monitoring/` 의 OTel Collector 가 도커 컨테이너 로그 파일(`/var/lib/docker/containers/*/*-json.log`)을 읽어 두 인덱스로 나눕니다. k8s 에선 같은 Collector 설정(`monitoring/otel/otel-collector.yml`)을 DaemonSet 로 옮기고 경로만 `/var/log/pods` 로 바꾸면 됩니다.

| 인덱스 | 무엇 | 기준 |
|---|---|---|
| `modu-app-logs` | 앱 스택 컨테이너 전부 — 서비스·게이트웨이·config·커머스 웹·콘솔 nginx. JSON 줄은 필드를 풀고(`attributes.service`, `requestId` …), JVM 경고 같은 비 JSON 줄은 `body` 그대로 | compose 프로젝트가 `modu-messenger`·`modu-platform`·`modu-commerce`·`modu_admin` |
| `modu-infra-logs` | MySQL·Kafka·Mongo·Redis·MinIO·exporter·OpenSearch 자신 등 | 그 밖의 프로젝트(`modu-data`, `monitoring` …) |

k8s 에선 `otel-collector` DaemonSet(`k8s/base/observability/otel-collector.yaml`)이 `/var/log/pods/modu_*` 를 읽어 `attributes.container`(컨테이너 이름)·`attributes.project: k8s` 를 붙입니다. (compose 시절의 `x-logging` 라벨 방식은 `monitoring/otel/` 에 참고용으로 남아 있습니다.)

- 대시보드: http://localhost:5601 (Discover → 인덱스 패턴 `modu-app-logs*`(기본) / `modu-infra-logs*`). dev 라 보안 플러그인은 꺼 두었고 9200 은 localhost 에만 열려 있습니다.
- 모든 앱 로그 줄에 MDC 가 붙습니다: `requestId`(게이트웨이가 `X-Request-Id` 로 발급·전파), `userId`, `service`, Pinpoint `PtxId`/`PspanId`. 한 요청을 따라가려면 `attributes.requestId:<id>` 로 검색합니다. `PtxId` 로는 Pinpoint 의 호출 트리와 맞춰 볼 수 있습니다.
- 접근 로그: 모든 서비스가 `event:http.access`(method, path, status, durationMs) 한 줄. 커머스는 `event:api.access` 로 요청·응답 헤더·본문(민감 헤더 마스킹, 4KB 까지)까지 남깁니다.

## 스키마 관리

MySQL 스키마는 애플리케이션이 아니라 DBA 가 gh-ost 로 바꿉니다(서비스는 `ddl-auto: validate`). 기준선·변경 이력·절차는 `data/mysql/` 에 있습니다.

- `data/mysql/DBA.md` — 원칙(외래키 없음, 두 버전 공존), 변경 한 건의 흐름, 방법 선택 표
- `data/mysql/schema/*.sql` — 스키마 기준선 7개, `schema/changes/` — 변경 이력, `schema/checks/` — 고아 행 점검
- `data/mysql/ghost.sh` — gh-ost 실행, `ghost-user-setup.sh` — gh-ost 계정, `dump-schema.sh` — 기준선 갱신, `check-orphans.sh` — 점검

## 운영 스크립트

- `data/kafka/*.sh`: 토픽 생성·조회·삭제. `copy-script.sh` 는 상대 경로로 스크립트 파일 이름을 참조하므로 반드시 `data/kafka` 디렉터리에서 실행해야 합니다 (kafka 컨테이너에 복사해서 사용).
- `data/debezium/*.sh`: 커넥터 등록·조회·삭제 (`create_connector.sh` 는 `data/.env` 의 비밀번호 사용)
- `data/mongodb/rs-init.sh`: replica set 최초 구성 (k8s: `kubectl -n modu exec mongo-01-0 -- bash /scripts/rs-init.sh`, 최초 1회만 — 지금 데이터는 이미 구성돼 있다)
- `data/mysql/replica-setup.sh <대상>`: MySQL 읽기·쓰기 분리. 소스(GTID·binlog ROW) → 레플리카 GTID 비동기 복제를 건다. `data/` 에서 실행, 여러 번 돌려도 된다.
  - 대상: `member` `chat` `push` `profile` `commerce`, 묶음 `messenger`(앞의 넷) `all`. (`mysql-commerce/replica-setup.sh` 는 `commerce` 를 부르는 껍데기)
  - 복제 계정 `repl` 과 앱 읽기 계정(메신저 `modu_ro`, 커머스 `commerce_ro`, SELECT 만)을 소스에 만든다(복제로 레플리카에 전파). 비밀번호는 `data/.env` 의 `MESSENGER_REPL_PASSWORD`·`MESSENGER_RO_PASSWORD`, `COMMERCE_REPL_PASSWORD`·`COMMERCE_RO_PASSWORD`.
  - 레플리카가 복제 중이 아니면 소스 DB 를 GTID 위치와 함께 덤프해 적재한 뒤 `SOURCE_AUTO_POSITION=1` 로 복제를 시작하고 `read_only`·`super_read_only` 를 `SET PERSIST` 로 켠다. 복제 중이면 계정만 맞춘다.
  - mysql-member 에는 `modu-chat`(회원)·`modu-point`(포인트)·`modu-schedule`(스케줄) 스키마가 함께 있다. 복제를 건 뒤 소스에서 만든 스키마는 복제로 따라온다.
  - 상태 확인: 레플리카에서 `SHOW REPLICA STATUS\G` (Replica_IO/SQL_Running, Seconds_Behind_Source)
  - `read_only` 를 레플리카 시작 옵션에 두면 이미지 첫 초기화가 root 비밀번호를 못 만든다 — 그래서 스크립트가 켠다.

## 주의사항

- 같은 이름의 다른 로컬 인프라 스택(monitoring, pinpoint-docker, mongodb 등)이 따로 떠 있으면 컨테이너 이름·포트가 겹쳐 동시에 띄울 수 없습니다.
- `data/.env` 의 비밀번호는 볼륨에 저장된 현재 비밀번호와 같아야 합니다 (healthcheck 가 사용).
- PVC 를 지우면(StorageClass reclaim Delete) 데이터도 지워집니다. `kubectl delete -k overlays/dev` 는 PVC 를 지우지 않지만 StatefulSet 을 지우고 다시 만들 때 이름이 같아야 같은 PVC 에 붙습니다.
