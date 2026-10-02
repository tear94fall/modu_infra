-- 2026-10-03  PK 없는 테이블 2개에 대리 PK 추가 (mysql-member / modu-chat)
-- gh-ost 는 PK(또는 유니크 키)가 없는 테이블을 다룰 수 없다. JPA @ElementCollection 테이블이라 매핑에는 id 가 없고,
-- 애플리케이션은 이 컬럼을 모른 채 INSERT 한다(AUTO_INCREMENT 가 채움). validate 는 매핑에 없는 컬럼을 신경 쓰지 않는다.
-- 적용 방식: 네이티브 DDL. AUTO_INCREMENT 컬럼 추가는 테이블 재작성 + 동시 DML 불가(짧은 잠금). 두 테이블 다 작아서 1초 미만.
-- 되돌리기: ALTER TABLE ... DROP COLUMN id;  (DROP PRIMARY KEY 가 같이 된다)

-- USE `modu-chat`;
ALTER TABLE `member_chat_room_members` ADD COLUMN `id` BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST;
ALTER TABLE `member_profiles`          ADD COLUMN `id` BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST;
