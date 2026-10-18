-- 2026-10-19  주문 표의 예전 적립 상태 컬럼 삭제 (commerce / commerce)  예상 행 수 ~40, gh-ost --auto-cutover
-- 구매 적립은 2026-10-18 에 point_outbox EARN 행으로 옮겼고(2026-10-18-point-outbox-earn.sql 백필, modu_commerce #56),
-- 코드가 더 이상 earn_status·earned_at 을 읽거나 쓰지 않는다(modu_commerce #57 — 이 코드가 롤아웃된 뒤에 적용한다).
-- earn_points·earn_rate(확정 적립액·적립률)는 그대로 둔다.
-- 적용(dev): sh data/mysql/ghost.sh commerce commerce orders "DROP COLUMN earn_status, DROP COLUMN earned_at" --execute --auto-cutover
-- 되돌리기(코드가 다시 쓰게 될 때만): ALTER TABLE orders ADD COLUMN earn_status VARCHAR(10) NOT NULL DEFAULT 'NONE', ADD COLUMN earned_at DATETIME(6) NULL
--   — 값은 복구되지 않는다(point_outbox EARN 행이 원본).
ALTER TABLE `orders`
  DROP COLUMN `earn_status`,
  DROP COLUMN `earned_at`;
