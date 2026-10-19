-- 2026-10-19  modu-schedule 스키마 삭제 (member / modu-schedule)  DROP DATABASE, 잠금 없음
-- 메신저 schedule-service 를 지웠다(modu_chat PR, 스케줄 0건·최근 24시간 실행 0건). 스케줄 작업은 modu_platform batch-service(modu-platform 스키마)가 맡는다.
-- 표 2개(schedule, shedlock) 모두 데이터 없음. 복제(mysql-member-replica)에는 DROP 이 복제로 따라간다.
-- 적용: schedule-service Deployment 를 지운 뒤(기동 때 validate 가 이 스키마를 본다). 기준선 파일 member.modu-schedule.sql 과 스크립트의 스키마 목록도 함께 지웠다.
-- 되돌리기: 2026-10-03 이전 기준선(git 이력의 member.modu-schedule.sql)으로 CREATE — 데이터는 없었으므로 복구할 것 없음.
DROP DATABASE IF EXISTS `modu-schedule`;
