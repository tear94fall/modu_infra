#!/bin/sh
# 커머스 복제 설정. 공통 스크립트(data/mysql/replica-setup.sh)로 옮겼다.
exec sh "$(dirname "$0")/../mysql/replica-setup.sh" commerce
