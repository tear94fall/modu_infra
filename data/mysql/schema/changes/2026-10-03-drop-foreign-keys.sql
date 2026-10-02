-- 2026-10-03  외래키 전부 제거 (운영 DB 에는 FK 를 두지 않는다 — 결정 배경은 ../../DBA.md)
-- 적용 방식: MySQL 8.0 네이티브 온라인 DDL. DROP FOREIGN KEY 는 INPLACE·LOCK=NONE, 테이블 재작성 없음.
--            (gh-ost 는 FK 가 걸린 테이블을 거부하므로 이 변경만은 gh-ost 로 할 수 없다)
-- FK 가 쓰던 인덱스는 그대로 남는다(조회 성능 변화 없음).
-- 제약 이름은 Hibernate 가 만든 해시라 환경마다 다를 수 있다. 다른 환경에 적용할 때는 아래 쿼리로 다시 뽑는다:
--   SELECT CONCAT('ALTER TABLE `', TABLE_NAME, '` DROP FOREIGN KEY `', CONSTRAINT_NAME, '`, ALGORITHM=INPLACE, LOCK=NONE;')
--   FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE();
-- 되돌리기: 기준선 이전 버전(git log schema/)의 CONSTRAINT 정의로 ADD FOREIGN KEY. 다만 고아 행이 있으면 실패한다.

-- ===== mysql-member / modu-chat =====
-- USE `modu-chat`;
ALTER TABLE `member_chat_room_members` DROP FOREIGN KEY `FKgy946gfx41sjuibt8xnml68v4`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `member_friend`            DROP FOREIGN KEY `FKjwh6qu4nkvej15skdydw7edn1`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `member_friend`            DROP FOREIGN KEY `FKk3wij0sds2e2f3730b6wfphxq`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `member_profiles`          DROP FOREIGN KEY `FKfxr2pw5n8s06oxydld097wxoq`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `staff_permission`         DROP FOREIGN KEY `FKibd4v5ok78sbw32ieks1l22jp`, ALGORITHM=INPLACE, LOCK=NONE;

-- ===== mysql-chat / modu-chat =====
-- USE `modu-chat`;
ALTER TABLE `chat`             DROP FOREIGN KEY `FK44b6elhh512d2722l09i6qdku`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `chat_room_member` DROP FOREIGN KEY `FKo6a9v51aal2574fjb1ldlw4di`, ALGORITHM=INPLACE, LOCK=NONE;

-- ===== mysql-commerce / commerce =====
-- USE `commerce`;
ALTER TABLE `attendance_checks`      DROP FOREIGN KEY `FKlj01x70c8uvvjpibcoycqwhgl`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `cart_items`             DROP FOREIGN KEY `FKia2f7yq196srm6ya3v96wafy6`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `categories`             DROP FOREIGN KEY `FKsaok720gsu4u2wrgbk10b5n8d`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `commerce_tier_coupons`  DROP FOREIGN KEY `FKluttwcawhl3s80c305i4yq6e7`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `coupon_scope_targets`   DROP FOREIGN KEY `FKbbm87kqysbftuucf350l4v5ml`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `order_items`            DROP FOREIGN KEY `FK2mbmbfy82tn7joyvldcdoim61`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `order_items`            DROP FOREIGN KEY `FKbioxgbv59vetrxe0ejfubep1w`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `order_items`            DROP FOREIGN KEY `FKocimc7dtr037rh4ls4l95nlfi`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `product_images`         DROP FOREIGN KEY `FKqnq71xsohugpqwf3c9gxmsuy`,  ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `product_option_groups`  DROP FOREIGN KEY `FKdux2pxpy018siooo4j11odfo8`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `product_option_values`  DROP FOREIGN KEY `FK8vnxnija6uvkgaas77t7shojv`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `product_skus`           DROP FOREIGN KEY `FKgfjst7dvihycy15ceiruv9roo`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `products`               DROP FOREIGN KEY `FKog2rp4qthbtt2lfyhfo32lsw9`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `promotion_coupons`      DROP FOREIGN KEY `FKoeaim6xof01b1w7vg6p13qtay`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `promotion_products`     DROP FOREIGN KEY `FKkn7hllhf1o8jjrolro4rqmxt7`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `reviews`                DROP FOREIGN KEY `FK2x2x74lnliqmt91bc1w95ll8n`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `reviews`                DROP FOREIGN KEY `FKpl51cejpw4gy5swfar8br9ngi`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `sku_option_values`      DROP FOREIGN KEY `FKj370ry8wjpbqpqo2e975sykjg`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `sku_option_values`      DROP FOREIGN KEY `FKjcok8ugbd079t27t13p9q61mu`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `user_coupons`           DROP FOREIGN KEY `FK9oi3p5xyfe4j32xs54nn7mi20`, ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE `wishlists`              DROP FOREIGN KEY `FKl7ao98u2bm8nijc1rv4jobcrx`, ALGORITHM=INPLACE, LOCK=NONE;
