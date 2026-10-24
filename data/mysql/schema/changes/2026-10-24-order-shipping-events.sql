-- 2026-10-24  주문 운영: 배송(택배사·송장·시작 시각)·취소(사유·주체) 컬럼 + 처리 이력 표 order_events (commerce / commerce)
-- 왜: 어드민 주문 운영 흐름(modu_commerce 주문 운영 PR) — 배송중으로 바꿀 때 택배사·송장번호를 적고, 직원 취소엔 사유를 남기며,
--     상태가 바뀔 때마다 order_events 에 한 줄(누가·언제·무엇으로) 쌓아 주문 상세의 타임라인으로 보여 준다. 고객 앱도 본다.
-- 예상 행 수: orders ~40 (gh-ost --auto-cutover), order_events 는 새 표(네이티브 CREATE).
-- 적용 순서: 이 DDL 먼저(앱은 validate — 컬럼이 없으면 새 코드가 못 뜬다), 그다음 commerce-service 배포. 옛 코드는 새 컬럼을 몰라도 돈다(전부 NULL 허용).
-- 적용(dev, 2026-10-24 01:08 KST 완료 — orders gh-ost auto-cutover 1분, order_events 네이티브 CREATE, _orders_*_del 삭제): sh data/mysql/ghost.sh commerce commerce orders "ADD COLUMN shipped_at DATETIME(6) NULL, ADD COLUMN carrier VARCHAR(30) NULL, ADD COLUMN tracking_no VARCHAR(40) NULL, ADD COLUMN cancel_reason VARCHAR(200) NULL, ADD COLUMN cancelled_by VARCHAR(20) NULL" --execute --auto-cutover
--           + 아래 CREATE TABLE 을 mysql-commerce-0 에서 직접(새 표라 잠금 없음).
-- 되돌리기: DROP TABLE order_events; ALTER TABLE orders DROP COLUMN shipped_at, DROP COLUMN carrier, DROP COLUMN tracking_no, DROP COLUMN cancel_reason, DROP COLUMN cancelled_by
--           — 코드가 그 컬럼을 안 쓰는 버전이 전부 배포된 뒤에.
ALTER TABLE `orders`
  ADD COLUMN `shipped_at` datetime(6) DEFAULT NULL,
  ADD COLUMN `carrier` varchar(30) DEFAULT NULL,
  ADD COLUMN `tracking_no` varchar(40) DEFAULT NULL,
  ADD COLUMN `cancel_reason` varchar(200) DEFAULT NULL,
  ADD COLUMN `cancelled_by` varchar(20) DEFAULT NULL;

CREATE TABLE `order_events` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `order_id` bigint NOT NULL,
  `from_status` varchar(20) DEFAULT NULL,
  `to_status` varchar(20) NOT NULL,
  `actor_type` varchar(20) NOT NULL,
  `actor_id` varchar(64) DEFAULT NULL,
  `reason` varchar(200) DEFAULT NULL,
  `carrier` varchar(30) DEFAULT NULL,
  `tracking_no` varchar(40) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_order_events_order` (`order_id`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
