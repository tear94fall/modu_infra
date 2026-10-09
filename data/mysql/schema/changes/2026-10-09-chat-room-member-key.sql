-- 2026-10-09  방 멤버 구성 키 (chat / modu-chat)  예상 행 수 30, gh-ost --auto-cutover
-- 같은 멤버 구성의 방이 동시 요청으로 두 개 생기는 것을 DB 가 직접 거절한다(잠금 테이블·격리 수준 변경 없이).
--   member_key = SHA2(정렬한 member_id 를 ',' 로 이은 값, 256). 방을 만들 때만 넣는다.
--   멤버가 들어오거나 나가면 NULL 로 비운다 — NULL 은 유니크 검사에서 빠지므로 구성이 바뀐 방끼리는 부딪히지 않는다.
--   즉 이 키는 "같은 구성으로 동시에 두 번 만들기"만 막는다. 기존 방 찾기는 지금처럼 멤버 목록으로 한다.
-- 적용: (1) 컬럼 추가 → (2) 기존 방 백필 → (3) 유니크 키 추가. 2026-10-09 기준 중복 구성 없음(방 30개).
-- 되돌리기(코드가 안 쓴 뒤): ALTER TABLE chat_room DROP INDEX uk_chat_room_member_key, DROP COLUMN member_key
ALTER TABLE `chat_room` ADD COLUMN `member_key` CHAR(64) COLLATE utf8mb4_0900_ai_ci NULL;

SET SESSION group_concat_max_len = 1048576;
UPDATE `chat_room` r
  JOIN (
    SELECT `chat_room_id`, SHA2(GROUP_CONCAT(`member_id` ORDER BY `member_id` SEPARATOR ','), 256) AS k
    FROM `chat_room_member` GROUP BY `chat_room_id`
  ) m ON m.`chat_room_id` = r.`chat_room_id`
SET r.`member_key` = m.k;

ALTER TABLE `chat_room` ADD UNIQUE KEY `uk_chat_room_member_key` (`member_key`);
