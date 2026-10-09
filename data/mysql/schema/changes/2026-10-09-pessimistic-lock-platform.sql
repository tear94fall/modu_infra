-- 2026-10-09  분산락 2차(DB) 비관적 잠금 테이블 (platform / modu-platform)  새 테이블, CREATE TABLE 직접(잠금 없음). dev 적용 2026-10-09
-- 1차 분산락(@ApiLock, Redis)이 뚫리거나 Redis 가 죽어도 정확성을 지키는 잠금. 이름 행을 (없으면 만들고) 트랜잭션 안에서
-- SELECT ... FOR UPDATE 로 잠그고, 커밋·롤백 때 풀린다. 이름이 끝없이 늘 수 있는 곳(채팅방 멤버 묶음)은 해시를 1024 칸으로 나눠 행 수를 묶는다.
-- 되돌리기(코드가 안 쓴 뒤): DROP TABLE pessimistic_lock;
CREATE TABLE IF NOT EXISTS `pessimistic_lock` (
  `name`       VARCHAR(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` DATETIME(6)  NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
