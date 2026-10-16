-- 스키마 기준선: mysql-platform / `modu-platform`  (sh mysql/dump-schema.sh platform 로 생성, 데이터 없음)

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
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
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
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
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
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
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `deployment` (
  `id` varchar(40) NOT NULL,
  `service` varchar(64) NOT NULL,
  `tag` varchar(128) NOT NULL,
  `previous_tag` varchar(128) DEFAULT NULL,
  `by_name` varchar(128) NOT NULL,
  `by_id` varchar(128) DEFAULT NULL,
  `status` varchar(16) NOT NULL,
  `step` varchar(16) NOT NULL,
  `percent` int NOT NULL DEFAULT '0',
  `started_at` datetime(6) NOT NULL,
  `finished_at` datetime(6) DEFAULT NULL,
  `error` text,
  `commit_sha` varchar(64) DEFAULT NULL,
  `commit_url` varchar(255) DEFAULT NULL,
  `steps_json` json NOT NULL,
  `rollout_json` json DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `running_service` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci GENERATED ALWAYS AS ((case when (`status` = _utf8mb4'RUNNING') then `service` end)) STORED,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_deployment_running_service` (`running_service`),
  KEY `idx_deployment_service_started` (`service`,`started_at` DESC),
  KEY `idx_deployment_started` (`started_at` DESC),
  KEY `idx_deployment_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `shedlock` (
  `name` varchar(64) NOT NULL,
  `lock_until` timestamp(3) NOT NULL,
  `locked_at` timestamp(3) NOT NULL,
  `locked_by` varchar(255) NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

