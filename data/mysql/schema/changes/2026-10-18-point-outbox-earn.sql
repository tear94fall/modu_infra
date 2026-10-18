-- 2026-10-18  구매 적립을 point_outbox EARN 으로 전환 (commerce / commerce)  스키마 변경 없음, 백필만.
-- 예전 경로(orders.earn_status) 의 적립 상태를 EARN 행으로 옮긴다. PENDING 은 릴레이가 보내고, DONE·FAILED 는 기록만 옮긴다.
-- 실행 시점: 새 commerce 파드만 남은 뒤(옛 파드가 마지막으로 남긴 PENDING 까지 포함하려고). 여러 번 실행해도 안전(NOT EXISTS).
-- 되돌리기: 백필 행은 created_at 이 모두 실행 시각 하나라서 그 값으로 지운다.
--   DELETE FROM point_outbox WHERE kind='EARN' AND created_at = '<실행 시각 UTC>';
-- 설계: modu_commerce docs/superpowers/specs/2026-10-18-purchase-earn-outbox-design.md §4.3·§4.5
INSERT INTO point_outbox (created_at, updated_at, kind, status, user_id, order_no, ref_id, amount, attempts, next_attempt_at, last_error, done_at)
SELECT UTC_TIMESTAMP(6), UTC_TIMESTAMP(6), 'EARN', o.earn_status, o.user_id, o.order_no,
       CONCAT('purchase:order:', o.id), o.earn_points, 0, UTC_TIMESTAMP(6),
       CASE WHEN o.earn_status = 'FAILED' THEN 'legacy: earn_status FAILED' END,
       CASE WHEN o.earn_status = 'DONE' THEN COALESCE(o.earned_at, o.delivered_at) END
FROM orders o
WHERE o.earn_points > 0 AND o.earn_status IN ('PENDING', 'DONE', 'FAILED')
  AND NOT EXISTS (SELECT 1 FROM point_outbox p WHERE p.kind = 'EARN' AND p.ref_id = CONCAT('purchase:order:', o.id));

-- 확인: 0 이어야 한다(폴백이 더 필요 없음). 0 이 아니면 그 행을 사람이 본다(earn_points > 0 인데 earn_status = 'NONE' 은 옛 코드에서 나올 수 없다).
SELECT COUNT(*) FROM orders o
WHERE o.earn_points > 0
  AND NOT EXISTS (SELECT 1 FROM point_outbox p WHERE p.kind = 'EARN' AND p.ref_id = CONCAT('purchase:order:', o.id));
