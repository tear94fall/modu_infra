-- 2026-10-17  배치 플랫폼(batch-service) 표 (platform / modu-platform)  새 표 4개, 네이티브 DDL(잠금 없음)
-- 모두 시스템 "배치" 탭: 잡 정의(batch_job), 회차(batch_job_run), 설정 변경 이력(batch_job_change), 파드 간 cron 중복 방지 락(shedlock).
-- 외래 키 없음(잡을 지워도 이력은 남는다). 앱(batch-service)은 validate 만 한다.
-- running_job_id = status 가 RUNNING 일 때만 batch_job_id, 아니면 NULL 인 생성 열 + 유니크 키 → 잡당 RUNNING 회차 하나(deployment.running_service 와 같은 수법).
-- 되돌리기: DROP TABLE batch_job_change, batch_job_run, batch_job; (shedlock 은 다른 서비스가 쓰지 않으면 DROP TABLE shedlock;)
USE `modu-platform`;

CREATE TABLE `batch_job` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `service` varchar(64) NOT NULL,
  `job_name` varchar(64) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `cron` varchar(64) NOT NULL,
  `zone` varchar(64) NOT NULL DEFAULT 'Asia/Seoul',
  `enabled` tinyint(1) NOT NULL DEFAULT '0',
  `timeout_seconds` int NOT NULL DEFAULT '600',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_batch_job_service_name` (`service`,`job_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `batch_job_run` (
  `id` varchar(40) NOT NULL,
  `batch_job_id` bigint NOT NULL,
  `service` varchar(64) NOT NULL,
  `job_name` varchar(64) NOT NULL,
  `trigger_type` varchar(16) NOT NULL,
  `triggered_by` varchar(128) DEFAULT NULL,
  `status` varchar(16) NOT NULL,
  `started_at` datetime(6) NOT NULL,
  `finished_at` datetime(6) DEFAULT NULL,
  `duration_ms` bigint DEFAULT NULL,
  `http_status` int DEFAULT NULL,
  `result_json` json DEFAULT NULL,
  `error` text,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `running_job_id` bigint GENERATED ALWAYS AS ((case when (`status` = _utf8mb4'RUNNING') then `batch_job_id` end)) STORED,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_batch_job_run_running` (`running_job_id`),
  KEY `idx_batch_job_run_job_started` (`batch_job_id`,`started_at` DESC),
  KEY `idx_batch_job_run_started` (`started_at` DESC),
  KEY `idx_batch_job_run_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `batch_job_change` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `batch_job_id` bigint NOT NULL,
  `changed_by` varchar(128) NOT NULL,
  `changed_at` datetime(6) NOT NULL,
  `field` varchar(32) NOT NULL,
  `before_value` varchar(255) DEFAULT NULL,
  `after_value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_batch_job_change_job` (`batch_job_id`,`changed_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS `shedlock` (
  `name` varchar(64) NOT NULL,
  `lock_until` timestamp(3) NOT NULL,
  `locked_at` timestamp(3) NOT NULL,
  `locked_by` varchar(255) NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
