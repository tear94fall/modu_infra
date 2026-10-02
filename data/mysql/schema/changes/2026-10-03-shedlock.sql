-- 2026-10-03  ShedLock 잠금 테이블 — 스케줄러가 있는 서비스의 스키마에만 (commerce, modu-schedule)
-- 파드가 2개 이상이어도 같은 잡이 한 번만 돌게 한다. 서비스 코드의 JdbcTemplateLockProvider 가 master 에서 이 행을 잠근다.
-- 적용 방식: CREATE TABLE (잠금 없음). 되돌리기: DROP TABLE shedlock;

-- USE `commerce`;        (mysql-commerce)
-- USE `modu-schedule`;   (mysql-member)
CREATE TABLE IF NOT EXISTS `shedlock` (
  `name`       VARCHAR(64)  NOT NULL,
  `lock_until` TIMESTAMP(3) NOT NULL,
  `locked_at`  TIMESTAMP(3) NOT NULL,
  `locked_by`  VARCHAR(255) NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
