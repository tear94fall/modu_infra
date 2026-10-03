# gh-ost (GitHub online schema migration) 실행용. ghost.sh 가 이 이미지를 k8s 의 일회용 파드로 띄운다(build-and-import.sh 로 노드에 넣는다).
# 릴리스 바이너리를 그대로 담는다 — https://github.com/github/gh-ost/releases
FROM debian:bookworm-slim
ARG GHOST_VERSION=1.1.11
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -fsSL "https://github.com/github/gh-ost/releases/download/v${GHOST_VERSION}/gh-ost-linux-${TARGETARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin gh-ost \
 && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /run/ghost
WORKDIR /run/ghost
ENTRYPOINT ["gh-ost"]
