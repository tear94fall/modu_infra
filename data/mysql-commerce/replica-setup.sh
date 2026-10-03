#!/bin/sh
# 커머스(mysql-commerce-0 → mysql-commerce-replica-0) 복제 설정. 공통 스크립트(data/mysql/replica-setup.sh)를 commerce 로 부른다.
#   sh data/mysql-commerce/replica-setup.sh      (NS=modu 기본)
set -eu
NS=${NS:-modu}
export NS
exec sh "$(dirname "$0")/../mysql/replica-setup.sh" commerce
