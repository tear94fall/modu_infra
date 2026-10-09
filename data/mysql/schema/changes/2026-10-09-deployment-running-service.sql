-- 2026-10-09  진행 중 배포 유일성 (platform / modu-platform)  행 수 21, 네이티브 DDL
-- 같은 서비스의 RUNNING 기록이 두 개 생기는 것을 DB 가 직접 거절한다(잠금 테이블·격리 수준 변경 없이).
--   running_service = status 가 RUNNING 일 때만 service, 아니면 NULL 인 생성 컬럼. 여기에 유니크 키.
--   배포가 끝나 status 가 바뀌면 값이 저절로 NULL 이 되어 다음 배포가 들어갈 수 있다(애플리케이션이 비울 필요 없음).
-- gh-ost 는 생성 컬럼을 다루지 못한다. 표가 작아 네이티브 DDL 로 적용한다(수십 ms).
-- 되돌리기(코드가 안 쓴 뒤): ALTER TABLE deployment DROP INDEX uk_deployment_running_service, DROP COLUMN running_service
ALTER TABLE `deployment`
  ADD COLUMN `running_service` VARCHAR(64) COLLATE utf8mb4_0900_ai_ci
    GENERATED ALWAYS AS (CASE WHEN `status` = 'RUNNING' THEN `service` END) STORED,
  ADD UNIQUE KEY `uk_deployment_running_service` (`running_service`);
