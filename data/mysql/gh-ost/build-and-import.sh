#!/bin/sh
# gh-ost 이미지(modu-gh-ost:1.1.11)를 만든다. ghost.sh 가 imagePullPolicy Never 로 이 이미지를 쓴다(레지스트리에 올리지 않는다).
# dev 는 Colima(k3s, docker 런타임 공유 — 2026-10-06 부터)라 docker build 만 하면 k8s 가 바로 본다. VM 을 다시 만들었을 때 다시 돌린다.
# (Docker Desktop 시절엔 docker save | ctr import 로 노드에 넣어야 했다.)
#   sh data/mysql/gh-ost/build-and-import.sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGE=modu-gh-ost:1.1.11
docker build -t "$IMAGE" "$HERE"
docker image inspect "$IMAGE" --format '{{.Id}} {{.Size}}'
