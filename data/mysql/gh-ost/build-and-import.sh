#!/bin/sh
# gh-ost 이미지(modu-gh-ost:1.1.11)를 만들어 Docker Desktop k8s 노드(desktop-control-plane 의 containerd, 네임스페이스 k8s.io)에 넣는다.
# ghost.sh 가 imagePullPolicy Never 로 이 이미지를 쓴다(레지스트리에 올리지 않는다). 노드를 다시 만들었을 때도 다시 돌린다.
#   sh data/mysql/gh-ost/build-and-import.sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGE=modu-gh-ost:1.1.11

docker build -t "$IMAGE" "$HERE"
docker save "$IMAGE" | docker exec -i desktop-control-plane ctr -n k8s.io images import -
docker exec desktop-control-plane ctr -n k8s.io images ls -q | grep -x "docker.io/library/$IMAGE"
