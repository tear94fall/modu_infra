-- 2026-11-15  카나리 배포 — 배포 기록에 모드와 카나리 상태 (platform / modu-platform)
-- 왜: 배포 탭의 "카나리 배포"(Argo Rollouts 단계 + 사람 승인). mode(DIRECT|CANARY), canary_json(단계·비율·새/옛 파드·이력). status 값에 ABORTED 가 추가되지만 varchar 라 DDL 없음.
-- 예상 행 수: deployment ~50 (gh-ost --auto-cutover). 적용 순서: 이 DDL 먼저(앱은 validate), 그다음 deploy-service(modu_platform 카나리 PR).
-- 적용(dev, 2026-11-15 완료): sh data/mysql/ghost.sh platform modu-platform deployment "ADD COLUMN mode VARCHAR(16) NOT NULL DEFAULT 'DIRECT', ADD COLUMN canary_json JSON NULL" --execute --auto-cutover
-- 되돌리기: ALTER TABLE deployment DROP COLUMN mode, DROP COLUMN canary_json — 코드가 그 컬럼을 안 쓰는 버전이 전부 배포된 뒤에.
ALTER TABLE `deployment`
  ADD COLUMN `mode` varchar(16) NOT NULL DEFAULT 'DIRECT',
  ADD COLUMN `canary_json` json DEFAULT NULL;
