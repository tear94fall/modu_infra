#!/usr/bin/env bash
# MinIO(file-storage 버킷) → Ceph RGW 로 객체 복사(메타데이터 포함). 2026-10-05 전환 때 한 번 쓴다. 양쪽 모두 클러스터 안 주소로,
# rclone 을 일회성 파드로 띄운다(이미지 rclone/rclone). 몇 번을 돌려도 같다(sync 가 아니라 copy — 대상 삭제 없음).
#   ./copy-from-minio.sh            # file-storage 복사
#   BUCKET=other ./copy-from-minio.sh
set -euo pipefail
NS=${NS:-modu}
BUCKET=${BUCKET:-file-storage}
MINIO_USER=$(kubectl -n "$NS" get sts minio -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MINIO_ROOT_USER")].value}')
MINIO_PASS=$(kubectl -n "$NS" get secret infra -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' | base64 -d)
RGW_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-modu-storage-service -o jsonpath='{.data.AccessKey}' | base64 -d)
RGW_SECRET=$(kubectl -n rook-ceph get secret rook-ceph-object-user-modu-storage-service -o jsonpath='{.data.SecretKey}' | base64 -d)
POD=rclone-copy-$RANDOM
kubectl -n "$NS" run "$POD" --rm -i --restart=Never --image=rclone/rclone:1.68 --image-pull-policy=IfNotPresent --command \
  --env="RCLONE_CONFIG_SRC_TYPE=s3" --env="RCLONE_CONFIG_SRC_PROVIDER=Minio" --env="RCLONE_CONFIG_SRC_ENDPOINT=http://minio:9000" \
  --env="RCLONE_CONFIG_SRC_ACCESS_KEY_ID=$MINIO_USER" --env="RCLONE_CONFIG_SRC_SECRET_ACCESS_KEY=$MINIO_PASS" \
  --env="RCLONE_CONFIG_DST_TYPE=s3" --env="RCLONE_CONFIG_DST_PROVIDER=Ceph" --env="RCLONE_CONFIG_DST_ENDPOINT=http://rgw:80" \
  --env="RCLONE_CONFIG_DST_ACCESS_KEY_ID=$RGW_KEY" --env="RCLONE_CONFIG_DST_SECRET_ACCESS_KEY=$RGW_SECRET" \
  -- sh -c "rclone mkdir dst:$BUCKET && rclone copy --metadata --checksum --stats-one-line -v src:$BUCKET dst:$BUCKET && echo '--- src' && rclone size src:$BUCKET && echo '--- dst' && rclone size dst:$BUCKET"
