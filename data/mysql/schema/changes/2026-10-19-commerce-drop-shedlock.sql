-- 2026-10-19  commerce 의 ShedLock 잠금 테이블 삭제 (commerce / commerce)  CREATE/DROP 만, 잠금 없음
-- commerce-service 안의 @Scheduled·ShedLock 을 지웠다(modu_commerce #59) — 잡 트리거는 batch-service 하나라 분산 잠금이 필요 없다.
-- 적용: modu_commerce #59 이미지가 롤아웃되고 옛 파드가 모두 사라진 뒤(옛 코드는 기동 때 이 테이블을 쓴다).
-- 되돌리기(코드가 다시 쓰게 될 때만): 2026-10-03-shedlock.sql 의 CREATE TABLE 을 다시 실행한다(잠금 행은 일회성이라 복구할 데이터 없음).
DROP TABLE IF EXISTS `shedlock`;
