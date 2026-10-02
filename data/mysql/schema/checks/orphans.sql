-- 고아 행 점검: 운영 DB 에 외래키가 없으므로 "부모 없는 자식 행"을 주기적으로 센다. 결과가 전부 0 이어야 정상.
-- 돌리는 법: sh mysql/check-orphans.sh   (모든 인스턴스, 아래 쿼리를 스키마별로 실행)
-- 짝은 2026-10-03 에 지운 외래키 28개 그대로다. 테이블·컬럼이 바뀌면 여기도 같이 고친다.
-- 형식: 한 줄에 하나, `-- @ <instance> <schema>` 로 대상이 바뀐다.

-- @ member modu-chat
SELECT 'member_chat_room_members.member_member_id' AS pair, COUNT(*) AS orphans FROM member_chat_room_members c LEFT JOIN member p ON p.member_id = c.member_member_id WHERE p.member_id IS NULL;
SELECT 'member_friend.member_id'                   AS pair, COUNT(*) AS orphans FROM member_friend c LEFT JOIN member p ON p.member_id = c.member_id WHERE p.member_id IS NULL;
SELECT 'member_friend.friend_member_id'            AS pair, COUNT(*) AS orphans FROM member_friend c LEFT JOIN member p ON p.member_id = c.friend_member_id WHERE p.member_id IS NULL;
SELECT 'member_profiles.member_member_id'          AS pair, COUNT(*) AS orphans FROM member_profiles c LEFT JOIN member p ON p.member_id = c.member_member_id WHERE p.member_id IS NULL;
SELECT 'staff_permission.member_id'                AS pair, COUNT(*) AS orphans FROM staff_permission c LEFT JOIN staff p ON p.member_id = c.member_id WHERE p.member_id IS NULL;

-- @ chat modu-chat
SELECT 'chat.chat_room_id'             AS pair, COUNT(*) AS orphans FROM chat c LEFT JOIN chat_room p ON p.chat_room_id = c.chat_room_id WHERE c.chat_room_id IS NOT NULL AND p.chat_room_id IS NULL;
SELECT 'chat_room_member.chat_room_id' AS pair, COUNT(*) AS orphans FROM chat_room_member c LEFT JOIN chat_room p ON p.chat_room_id = c.chat_room_id WHERE c.chat_room_id IS NOT NULL AND p.chat_room_id IS NULL;

-- @ commerce commerce
SELECT 'attendance_checks.promotion_id'       AS pair, COUNT(*) AS orphans FROM attendance_checks c LEFT JOIN promotions p ON p.id = c.promotion_id WHERE p.id IS NULL;
SELECT 'cart_items.sku_id'                    AS pair, COUNT(*) AS orphans FROM cart_items c LEFT JOIN product_skus p ON p.id = c.sku_id WHERE p.id IS NULL;
SELECT 'categories.parent_id'                 AS pair, COUNT(*) AS orphans FROM categories c LEFT JOIN categories p ON p.id = c.parent_id WHERE c.parent_id IS NOT NULL AND p.id IS NULL;
SELECT 'commerce_tier_coupons.tier_code'      AS pair, COUNT(*) AS orphans FROM commerce_tier_coupons c LEFT JOIN commerce_tiers p ON p.code = c.tier_code WHERE p.code IS NULL;
SELECT 'coupon_scope_targets.coupon_id'       AS pair, COUNT(*) AS orphans FROM coupon_scope_targets c LEFT JOIN coupons p ON p.id = c.coupon_id WHERE p.id IS NULL;
SELECT 'order_items.sku_id'                   AS pair, COUNT(*) AS orphans FROM order_items c LEFT JOIN product_skus p ON p.id = c.sku_id WHERE p.id IS NULL;
SELECT 'order_items.order_id'                 AS pair, COUNT(*) AS orphans FROM order_items c LEFT JOIN orders p ON p.id = c.order_id WHERE p.id IS NULL;
SELECT 'order_items.product_id'               AS pair, COUNT(*) AS orphans FROM order_items c LEFT JOIN products p ON p.id = c.product_id WHERE p.id IS NULL;
SELECT 'product_images.product_id'            AS pair, COUNT(*) AS orphans FROM product_images c LEFT JOIN products p ON p.id = c.product_id WHERE p.id IS NULL;
SELECT 'product_option_groups.product_id'     AS pair, COUNT(*) AS orphans FROM product_option_groups c LEFT JOIN products p ON p.id = c.product_id WHERE p.id IS NULL;
SELECT 'product_option_values.group_id'       AS pair, COUNT(*) AS orphans FROM product_option_values c LEFT JOIN product_option_groups p ON p.id = c.group_id WHERE p.id IS NULL;
SELECT 'product_skus.product_id'              AS pair, COUNT(*) AS orphans FROM product_skus c LEFT JOIN products p ON p.id = c.product_id WHERE p.id IS NULL;
SELECT 'products.category_id'                 AS pair, COUNT(*) AS orphans FROM products c LEFT JOIN categories p ON p.id = c.category_id WHERE c.category_id IS NOT NULL AND p.id IS NULL;
SELECT 'promotion_coupons.promotion_id'       AS pair, COUNT(*) AS orphans FROM promotion_coupons c LEFT JOIN promotions p ON p.id = c.promotion_id WHERE p.id IS NULL;
SELECT 'promotion_products.promotion_id'      AS pair, COUNT(*) AS orphans FROM promotion_products c LEFT JOIN promotions p ON p.id = c.promotion_id WHERE p.id IS NULL;
SELECT 'reviews.order_item_id'                AS pair, COUNT(*) AS orphans FROM reviews c LEFT JOIN order_items p ON p.id = c.order_item_id WHERE p.id IS NULL;
SELECT 'reviews.product_id'                   AS pair, COUNT(*) AS orphans FROM reviews c LEFT JOIN products p ON p.id = c.product_id WHERE p.id IS NULL;
SELECT 'sku_option_values.sku_id'             AS pair, COUNT(*) AS orphans FROM sku_option_values c LEFT JOIN product_skus p ON p.id = c.sku_id WHERE p.id IS NULL;
SELECT 'sku_option_values.option_value_id'    AS pair, COUNT(*) AS orphans FROM sku_option_values c LEFT JOIN product_option_values p ON p.id = c.option_value_id WHERE p.id IS NULL;
SELECT 'user_coupons.coupon_id'               AS pair, COUNT(*) AS orphans FROM user_coupons c LEFT JOIN coupons p ON p.id = c.coupon_id WHERE p.id IS NULL;
SELECT 'wishlists.product_id'                 AS pair, COUNT(*) AS orphans FROM wishlists c LEFT JOIN products p ON p.id = c.product_id WHERE p.id IS NULL;
