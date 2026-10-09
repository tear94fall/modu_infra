-- 2026-10-09  주문 생성 멱등 키 (commerce / commerce)  예상 행 수 ~30, gh-ost --auto-cutover
-- 결제 응답을 못 받고 다시 누른 요청이 주문을 두 번 만들지 않게 한다. 웹이 결제 화면마다 만든 키를 Idempotency-Key 헤더로 보내고,
-- 서비스는 (user_id, idempotency_key) 로 이미 만든 주문이 있으면 그 주문을 돌려준다. 키 없는 옛 요청은 NULL 이라 유니크에 걸리지 않는다.
-- 적용(dev, 2026-10-09 09:38 KST 완료): sh data/mysql/ghost.sh commerce commerce orders "ADD COLUMN idempotency_key VARCHAR(64) NULL, ADD UNIQUE KEY uk_orders_user_idempotency (user_id, idempotency_key)" --execute --auto-cutover
-- 되돌리기(코드가 안 쓴 뒤): ALTER TABLE orders DROP INDEX uk_orders_user_idempotency, DROP COLUMN idempotency_key
ALTER TABLE `orders`
  ADD COLUMN `idempotency_key` VARCHAR(64) COLLATE utf8mb4_unicode_ci NULL,
  ADD UNIQUE KEY `uk_orders_user_idempotency` (`user_id`, `idempotency_key`);
