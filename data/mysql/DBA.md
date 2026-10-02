# DB 스키마 운영 절차 (DBA)

2026-10-03 부터 MySQL 스키마는 **애플리케이션이 아니라 DBA 가** 바꾼다. 서비스는 `ddl-auto: validate` 로 떠서
코드와 DB 가 어긋나면 기동에 실패한다(조용히 테이블을 바꾸는 일은 없다). 변경은 gh-ost 로 온라인 적용한다.

## 원칙

- **외래키를 두지 않는다.** 2026-10-03 에 28개를 전부 지웠다(`schema/changes/2026-10-03-drop-foreign-keys.sql`).
  이유: gh-ost 는 FK 가 걸린 테이블을 다루지 못하고, 샤딩·서비스 분리와 맞지 않으며, 부모 행 잠금이 쓰기 성능과
  데드락에 영향을 준다. 정합성은 (1) 애플리케이션 UseCase 가 쓰기 전에 부모를 확인, (2) 물리 삭제 대신 soft delete,
  (3) 유니크 키·인덱스는 그대로 유지, (4) 고아 행 점검(`check-orphans.sh`)으로 지킨다.
  테스트(H2)는 Hibernate `update` 라 FK 가 살아 있어 삭제 순서 버그는 테스트가 잡는다.
- **모든 테이블에 PK.** gh-ost 요건. PK 없던 `member_chat_room_members`·`member_profiles` 에 대리 PK 를 넣었다.
- **두 버전이 같이 떠 있어도 되는 변경만.** 롤링 배포 중에는 구버전·신버전 코드가 같은 DB 를 쓴다.
  추가는 코드보다 먼저, 삭제는 코드가 안 쓴 뒤에. 이름 변경은 하지 않는다(새 컬럼 추가 → 양쪽 쓰기 → 옛 컬럼 삭제).
- **기준선이 곧 운영 DB 모양.** `schema/<instance>.<schema>.sql` 은 변경을 적용한 뒤 `dump-schema.sh` 로 다시 뜬다.
  변경 SQL 과 새 기준선은 같은 PR 에 들어간다.

## 디렉터리

| 경로 | 내용 |
|---|---|
| `schema/<instance>.<schema>.sql` | 스키마 기준선 7개 (member: modu-chat·modu-point·modu-schedule, chat·push·profile: modu-chat, commerce: commerce). 데이터 없음 |
| `schema/changes/YYYY-MM-DD-<topic>.sql` | 변경 이력. 파일 머리에 대상·사유·적용 방식·되돌리기 |
| `schema/checks/orphans.sql` | 고아 행 점검 쿼리(지운 FK 28쌍) |
| `dump-schema.sh` | 기준선 다시 뜨기 |
| `ghost.sh` | gh-ost 실행 래퍼 |
| `ghost-user-setup.sh` | gh-ost 계정(`ghost`) 만들기 — 소스마다 한 번 |
| `check-orphans.sh` | 고아 행 점검 실행(레플리카에서) |
| `gh-ost/Dockerfile` | gh-ost 1.1.11 이미지 (`modu-gh-ost:1.1.11`, ghost.sh 가 없으면 만든다) |

인스턴스 ↔ 컨테이너: `member|chat|push|profile|commerce` → 소스 `mysql-<instance>`, 레플리카 `mysql-<instance>-replica`.

## 변경 한 건의 흐름

1. **개발자**: 엔티티를 고치고, `schema/changes/YYYY-MM-DD-<topic>.sql` 을 쓴다.
   ```sql
   -- 2026-10-05  orders 에 선물 메시지 (commerce / commerce)  예상 행 수 30, gh-ost
   -- 되돌리기: ALTER TABLE orders DROP COLUMN gift_message
   ALTER TABLE `orders` ADD COLUMN `gift_message` VARCHAR(200) NULL;
   ```
   PR 두 개: modu_infra(변경 SQL + 기준선) → 서비스 코드. 코드 PR 설명에 "선행 SQL: <파일>" 을 적는다.
2. **DBA 검토**: 아래 "어떤 방법으로" 표로 방식을 정한다. 두 버전 공존 원칙에 어긋나면(컬럼 삭제를 코드보다 먼저 등) 돌려보낸다.
3. **검사만 먼저**: `sh mysql/ghost.sh commerce commerce orders "ADD COLUMN gift_message VARCHAR(200) NULL"`
   (`--execute` 없음) — 권한·바이너리 로그·행 수·레플리카 연결을 확인하고 그림자 테이블을 만들었다 지운다.
4. **적용**: 같은 명령에 `--execute`. 복사가 끝나면 cut-over 직전에 멈춰 기다린다(`mysql/ghost-run/<table>.postpone`).
   로그에서 `Copy: 100%`, `Lag` 가 낮은지 보고 `rm mysql/ghost-run/<table>.postpone` 하면 교체한다(1초 안팎, 그동안 그 테이블 쿼리만 잠깐 막힘).
   작은 테이블은 `--auto-cutover` 로 바로 교체해도 된다.
5. **확인**: 레플리카에 반영됐는지(`SHOW REPLICA STATUS`, 테이블 구조), 서비스 로그에 에러 없는지.
   원래 테이블은 `_<table>_<timestamp>_del` 로 남아 있다. 하루쯤 두고 문제 없으면 `DROP TABLE` 한다(되돌릴 때 쓴다).
6. **기준선 갱신**: `sh mysql/dump-schema.sh commerce` → diff 가 의도한 변경만인지 보고 PR 에 넣는다. 변경 파일 머리에 적용 일시를 적는다.
7. **코드 배포**. `validate` 가 통과하면 끝. 실패하면 SQL 이 빠졌거나 타입이 다른 것이니 코드를 DB 에 맞춘다.

## 어떤 방법으로

| 변경 | 방법 | 비고 |
|---|---|---|
| 컬럼 추가(NULL 허용 또는 기본값) | gh-ost | 작으면 `--auto-cutover`. 8.0 `ALGORITHM=INSTANT` 로 직접 해도 되지만 절차를 하나로 두려고 gh-ost 를 기본으로 한다 |
| 인덱스 추가·삭제 | gh-ost | 행 수에 비례해 시간. 서비스는 안 멈춤 |
| 컬럼 타입 변경, NOT NULL 전환, 길이 축소 | gh-ost | 데이터가 안 맞는 행이 있으면 복사 중 실패. 먼저 쿼리로 확인 |
| 컬럼 삭제 | gh-ost | **코드가 그 컬럼을 안 쓰는 버전이 전부 배포된 뒤에** |
| 새 테이블 | `CREATE TABLE` 직접 | 잠금 없음. 기준선에 추가 |
| 테이블 삭제 | `DROP TABLE` 직접 | 코드가 안 쓴 뒤에. 먼저 `RENAME` 으로 하루 두는 것도 방법 |
| 외래키 추가 | 하지 않는다 | 원칙 |
| PK 추가/변경 | 네이티브 DDL(`ALGORITHM=INPLACE`) | gh-ost 는 PK 없는 테이블을 못 다룬다. 짧은 잠금 |
| 데이터 백필(기존 행 채우기) | 1만 행씩 끊어서 UPDATE | 한 번에 하면 레플리카 지연·롤백 세그먼트 폭증 |
| 큰 테이블 쪼개기(파티션·분리) | 별도 설계 | gh-ost 범위 밖 |

gh-ost 가 **못 하는 것**: FK 있는 테이블(우리는 없음), PK/유니크 키 없는 테이블, 트리거 있는 테이블, 같은 테이블 동시 두 개 변경, `RENAME` 자체.

## gh-ost 가 도는 방식 (ghost.sh)

- `--host=mysql-<instance>-replica`: **레플리카**에 붙어 바이너리 로그를 읽고(ROW 형식, `log_replica_updates=ON`), 소스는
  `SHOW REPLICA STATUS` 로 찾아 거기에 쓴다. 소스에 바이너리 로그 읽기 부하를 주지 않는다.
- `--assume-rbr`: SUPER 없이 돈다(이미 ROW 라서).
- `--throttle-control-replicas=<replica> --max-lag-millis=1500`: 레플리카 지연이 1.5초를 넘으면 복사를 멈췄다 재개.
- `--max-load=Threads_running=25`(넘으면 쉬엄쉬엄) / `--critical-load=Threads_running=60`(넘으면 중단).
- `--chunk-size=1000`, `--default-retries=120`, `--timestamp-old-table`, `--initially-drop-ghost-table`(이전 실패 잔재 정리).
- 계정 `ghost`: 대상 스키마에 ALTER CREATE DELETE DROP INDEX INSERT LOCK TABLES SELECT TRIGGER UPDATE, 전역 REPLICATION CLIENT·SLAVE,
  `performance_schema` SELECT + `setup_instruments` UPDATE(cut-over 때 메타데이터 잠금을 본다). 비밀번호는 `data/.env` 의 `GHOST_PASSWORD`.
- 실행 중 조작은 `mysql/ghost-run/` 의 플래그 파일: `<table>.postpone`(지우면 cut-over), `<table>.throttle`(만들면 일시정지),
  `<table>.panic`(만들면 즉시 중단).

2026-10-03 dev 에서 확인: `commerce.wishlists` 를 `ENGINE=InnoDB`(내용 없는 재작성)로 `--execute` → 복사 1초, cut-over 잠금 0.8~1.1초,
소스·레플리카 모두 행 수·max(id) 일치, `_wishlists_<ts>_del` 남음 → DROP.

## 정기 점검

- `sh mysql/check-orphans.sh` — 주 1회 또는 큰 삭제 작업 뒤. 레플리카에서 읽는다. 0 이 아닌 짝이 나오면 해당 UseCase 의 삭제 순서를 본다.
- `SHOW REPLICA STATUS\G` — IO/SQL `Yes`, `Seconds_Behind_Source` 0 근처.
- `_<table>_<ts>_del` 잔재가 남아 있지 않은지(`SHOW TABLES LIKE '\_%\_del'`).

## 다른 환경(스테이징·운영)에 처음 적용할 때

1. `data/.env` 에 `GHOST_PASSWORD` → `sh mysql/ghost-user-setup.sh`.
2. `schema/changes/` 를 날짜순으로 적용. 단 `2026-10-03-drop-foreign-keys.sql` 의 제약 이름은 환경마다 다르니 파일 머리의 쿼리로 다시 뽑는다.
3. 적용 뒤 `dump-schema.sh` 결과가 저장소의 기준선과 같은지 diff 로 확인한다(다르면 그 환경에 손으로 바꾼 흔적이 있는 것).
