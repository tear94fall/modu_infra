-- 2026-11-15  deploy-service 배포 플로우를 Temporal 워크플로로 옮기며 기록 ↔ 실행을 잇는 컬럼 (platform / modu-platform)
-- 왜: 배포 한 건이 Temporal 워크플로 deploy-<service> 의 한 실행(run)이 된다. 콘솔 배포 기록 상세의 "Temporal 에서 보기" 링크가
--     /namespaces/platform/workflows/deploy-<service>/<workflow_run_id>/history 를 가리킨다. NULL 허용 — 옛 기록·옛 코드는 몰라도 된다.
-- 예상 행 수: deployment ~36 (gh-ost --auto-cutover). 생성 컬럼 running_service 가 있는 표라 gh-ost 가 거절하면 ALGORITHM=INSTANT 로 직접(아래 기록).
-- 적용 순서: 이 DDL 먼저(앱은 validate — 컬럼이 없으면 새 deploy-service 가 못 뜬다), 그다음 deploy-service(modu_platform) 배포.
-- 적용(dev, 2026-11-14 23:24 KST 완료 — 36행, 복사 1초, auto-cutover, _deployment_*_del 삭제. 생성 컬럼이 있어도 gh-ost 1.1.11 이 그대로 처리했다):
--   sh data/mysql/ghost-user-setup.sh platform   # mysql-platform 에는 ghost 계정이 없었다(처음)
--   sh data/mysql/ghost.sh platform modu-platform deployment "ADD COLUMN workflow_run_id VARCHAR(64) NULL" --execute --auto-cutover
-- 되돌리기: ALTER TABLE deployment DROP COLUMN workflow_run_id — 코드가 그 컬럼을 안 쓰는 버전이 전부 배포된 뒤에.
ALTER TABLE `deployment`
  ADD COLUMN `workflow_run_id` varchar(64) DEFAULT NULL;
