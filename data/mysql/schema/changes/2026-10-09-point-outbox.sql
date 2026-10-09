-- 2026-10-09  포인트 아웃박스 (commerce / commerce)  새 테이블, CREATE TABLE 직접(잠금 없음). dev 적용 2026-10-09 09:38 KST
-- point-service 호출과 주문 커밋이 어긋나지 않게 한다.
--   SPEND_GUARD: 주문 차감 전에 별도 트랜잭션으로 남긴다. 복구 작업이 주문이 없으면 point-service 에 차감 취소를 보낸다.
--   REFUND:      주문 취소와 같은 트랜잭션에 남기고, 커밋 뒤 환불을 보낸다. 실패하면 복구 작업이 재시도한다.
-- ref_id 는 원래 차감 키(order:<주문번호>). point-service 쪽 환불 키는 refund:<ref_id> 하나라 두 경로가 겹쳐도 한 번만 돌려준다.
-- 되돌리기(코드가 안 쓴 뒤): DROP TABLE point_outbox;
CREATE TABLE IF NOT EXISTS `point_outbox` (
  `id`              BIGINT       NOT NULL AUTO_INCREMENT,
  `created_at`      DATETIME(6)  NOT NULL,
  `updated_at`      DATETIME(6)  NOT NULL,
  `kind`            VARCHAR(16)  COLLATE utf8mb4_unicode_ci NOT NULL,
  `status`          VARCHAR(10)  COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id`         VARCHAR(64)  COLLATE utf8mb4_unicode_ci NOT NULL,
  `order_no`        VARCHAR(20)  COLLATE utf8mb4_unicode_ci NOT NULL,
  `ref_id`          VARCHAR(128) COLLATE utf8mb4_unicode_ci NOT NULL,
  `amount`          BIGINT       NOT NULL,
  `attempts`        INT          NOT NULL DEFAULT 0,
  `next_attempt_at` DATETIME(6)  NOT NULL,
  `last_error`      VARCHAR(300) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `done_at`         DATETIME(6)  DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_point_outbox_kind_ref` (`kind`, `ref_id`),
  KEY `idx_point_outbox_status_next` (`status`, `next_attempt_at`),
  KEY `idx_point_outbox_order_no` (`order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
