# modu_infra

modu 프로젝트(modu_messenger, modu_commerce)가 같이 쓰는 인프라와 관측성 스택입니다.
각 프로젝트의 `backend/docker-compose.yml` 에는 애플리케이션 서비스만 있고, 인프라는 여기서 먼저 띄웁니다.

이 저장소 옆에 다음 두 저장소가 clone 되어 있다고 가정합니다.

- modu_messenger — https://github.com/tear94fall/modu_chat (경로: `../modu_chat`)
- modu_commerce — https://github.com/tear94fall/modu_commerce (경로: `../modu_commerce`)

## 구성

| 디렉터리 | compose 프로젝트 | 내용 |
|---|---|---|
| `data/` | `modu-data` | MySQL 5, MongoDB replica set 3, Redis 단일 + 클러스터 6, ZooKeeper, Kafka, kafka-ui, Debezium, RabbitMQ, MinIO |
| `monitoring/` | `monitoring` | Prometheus, Grafana, node/cadvisor/mysqld/redis/mongodb/kafka exporter |
| `pinpoint-docker/` | `pinpoint-docker` | Pinpoint APM. [pinpoint-apm/pinpoint-docker](https://github.com/pinpoint-apm/pinpoint-docker) 기반에 로컬 수정 포함: 네트워크 서브넷·collector IP, 웹 포트 18080, `docker-compose.override.yml`(pinpoint-mysql 13306, redis 16379 — data 스택 포트와 충돌 회피) |

data·monitoring 컨테이너와 modu_messenger·modu_commerce 서비스는 external 네트워크 `modu-infra` 에 붙고, 서비스는 컨테이너 이름(`mysql-chat`, `kafka`, `redis` …)으로 인프라에 접근합니다.
pinpoint-docker 는 자체 네트워크 `pinpoint-docker_pinpoint` 를 쓰며, modu_messenger 서비스가 에이전트 연동을 위해 이 네트워크에도 붙습니다.
Redis 클러스터 노드는 data 스택의 클러스터 전용 네트워크 `modu-data_redis-cluster` 의 고정 IP 를 광고하므로, modu_messenger 의 auth-service·member-service 는 이 네트워크에도 external 로 붙습니다. 그래서 data 스택의 compose 프로젝트 이름(`modu-data`)을 바꾸면 안 됩니다.

## 최초 준비

```bash
docker network create modu-infra
cp data/.env.example data/.env          # 값 채우기 (MINIO_DATA_DIR 포함 — minio 데이터를 bind mount 할 호스트 경로)
# monitoring/.env, monitoring/mysql/.my.cnf, data/mongodb/mongodb.key 도 필요합니다 (git 제외)
```

## 스키마 관리

MySQL 스키마는 애플리케이션이 아니라 DBA 가 gh-ost 로 바꿉니다(서비스는 `ddl-auto: validate`). 기준선·변경 이력·절차는 `data/mysql/` 에 있습니다.

- `data/mysql/DBA.md` — 원칙(외래키 없음, 두 버전 공존), 변경 한 건의 흐름, 방법 선택 표
- `data/mysql/schema/*.sql` — 스키마 기준선 7개, `schema/changes/` — 변경 이력, `schema/checks/` — 고아 행 점검
- `data/mysql/ghost.sh` — gh-ost 실행, `ghost-user-setup.sh` — gh-ost 계정, `dump-schema.sh` — 기준선 갱신, `check-orphans.sh` — 점검

## 기동 순서

1. `cd pinpoint-docker && docker compose up -d` — 계속 띄워 둘 필요는 없지만, modu_messenger 가 external 네트워크 `pinpoint-docker_pinpoint` 와 볼륨 `pinpoint-docker_data-volume` 을 참조하므로 messenger 를 처음 띄우기 전에 한 번은 `up` 을 해서 이 둘을 만들어 둬야 합니다. `docker network create pinpoint-docker_pinpoint` 로 네트워크만 만드는 것은 대체가 안 됩니다 — pinpoint-docker 는 이 네트워크에 고정 서브넷과 collector 고정 IP 를 기대하기 때문입니다. 그러니 한 번은 실제로 `up` 하는 것을 권장합니다. (HBase 준비에 수 분)
2. `cd data && docker compose up -d`
3. `cd monitoring && docker compose up -d`
4. `cd ../modu_chat/backend && docker compose up -d` (modu_messenger)
5. `cd ../modu_commerce/backend && docker compose up -d` (modu_commerce)

프로젝트 사이에는 `depends_on` 을 걸 수 없어서, 인프라가 늦게 뜨면 서비스는 restart 정책으로 재시도합니다.

Redis 클러스터는 별도 init 컨테이너 없이 `redis-node-1` 이 직접 만듭니다. 기동할 때 6노드가 모두 응답하면 슬롯이 비어 있을 때(최초 1회)만 `redis-cli --cluster create` 를 실행하고, 이미 구성돼 있으면 `docker logs redis-node-1` 에 `redis cluster already formed` 가 남습니다. `redis-node-1` 은 `cluster_state:ok` 가 되어야 healthy 입니다.

## 접속 주소와 포트

| 대상 | 호스트 포트 |
|---|---|
| mysql-member / chat / push / profile (쓰기, 복제 소스) | 3306 / 3307 / 3308 / 3309 |
| mysql-member-replica / chat / push / profile (읽기, 복제 레플리카) | 3326 / 3327 / 3328 / 3329 |
| mysql-commerce (쓰기, 복제 소스) | 3316 |
| mysql-commerce-replica (읽기, 복제 레플리카) | 3317 |
| mongo-01 / 02 / 03 | 27017 / 27018 / 27019 |
| redis (단일) | 6379 |
| redis-node-1~6 | 호스트 포트 없음 (modu-infra 네트워크에서 `redis-node-N:6379`) |
| zookeeper | 2181 |
| kafka | 29092 (호스트), 컨테이너 간 `kafka:9092` |
| kafka-ui | http://localhost:9009 |
| debezium | http://localhost:8083 |
| rabbitmq | 5672, 관리 http://localhost:15672, 클러스터/CLI 25672 |
| minio | 9000, 콘솔 http://localhost:9001 |
| Prometheus | http://localhost:19090 |
| Grafana | http://localhost:3000 |
| Pinpoint | http://localhost:18080 (pinpoint-mysql 13306, pinpoint redis 16379) |

## 운영 스크립트

- `data/kafka/*.sh`: 토픽 생성·조회·삭제. `copy-script.sh` 는 상대 경로로 스크립트 파일 이름을 참조하므로 반드시 `data/kafka` 디렉터리에서 실행해야 합니다 (kafka 컨테이너에 복사해서 사용).
- `data/debezium/*.sh`: 커넥터 등록·조회·삭제 (`create_connector.sh` 는 `data/.env` 의 비밀번호 사용)
- `data/mongodb/rs-init.sh`: replica set 최초 구성 (`docker exec mongo-01 bash /scripts/rs-init.sh`, 최초 1회만)
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
- 볼륨을 지우는 명령(`docker compose down -v`, `docker volume prune`)은 데이터를 지웁니다.
