-- 스키마 기준선: mysql-platform / `modu-platform`  (2026-10-07 처음 만들 때 손으로 쓴 DDL = k8s/base/data/mysql-platform-init.sql; 이후 변경은 sh mysql/dump-schema.sh platform 으로 갱신)

CREATE TABLE IF NOT EXISTS `deployment` (
  `id`            varchar(40)   NOT NULL,
  `service`       varchar(64)   NOT NULL,
  `tag`           varchar(128)  NOT NULL,
  `previous_tag`  varchar(128)  DEFAULT NULL,
  `by_name`       varchar(128)  NOT NULL,
  `by_id`         varchar(128)  DEFAULT NULL,
  `status`        varchar(16)   NOT NULL,
  `step`          varchar(16)   NOT NULL,
  `percent`       int           NOT NULL DEFAULT 0,
  `started_at`    datetime(6)   NOT NULL,
  `finished_at`   datetime(6)   DEFAULT NULL,
  `error`         text,
  `commit_sha`    varchar(64)   DEFAULT NULL,
  `commit_url`    varchar(255)  DEFAULT NULL,
  `steps_json`    json          NOT NULL,
  `rollout_json`  json          DEFAULT NULL,
  `created_at`    datetime(6)   NOT NULL,
  `updated_at`    datetime(6)   NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_deployment_service_started` (`service`, `started_at` DESC),
  KEY `idx_deployment_started` (`started_at` DESC),
  KEY `idx_deployment_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
