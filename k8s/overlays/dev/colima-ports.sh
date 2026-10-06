#!/usr/bin/env bash
# Colima(k3s)에서 LoadBalancer 포트를 Mac 으로 내보낸다(2026-10-06). k3s 의 ServiceLB 는 VM 안 iptables 로 포트를 여는데 Lima 의 포트 포워딩은
# "소켓으로 듣는 포트"만 Mac 으로 넘기므로 LB 포트가 Mac 에 안 보인다. 그래서 VM 의 docker 로 nginx(stream) 컨테이너를 띄워 각 포트를 VM IP 의
# 같은 포트로 넘기고(-p 로 docker-proxy 가 0.0.0.0 으로 듣는다 → Lima 가 Mac 의 모든 인터페이스로 포워딩), 결과적으로 localhost·192.168.0.x 에서
# compose/Docker Desktop 시절과 같은 주소가 된다(안드로이드 앱의 192.168.0.3:8000 도 그대로).
#   ./colima-ports.sh            # (재)생성. colima 를 다시 만들었거나 포트를 추가했을 때 다시 돌린다 — restart=unless-stopped 라 재부팅엔 살아난다.
#   ./colima-ports.sh down
set -euo pipefail
NAME=modu-ports
PORTS="8000 8888 8081 8084 8085 8082 5601 9200 3000 19090 9009 15672 8090 7480 7001"   # 게이트웨이 config 콘솔3 웹 OpenSearch(2) Grafana Prometheus kafka-ui RabbitMQ Argo RGW Ceph대시보드
VM_IP=${VM_IP:-$(colima ls --json | python3 -c 'import sys,json; print(json.load(sys.stdin)["ip_address"])')}
docker rm -f "$NAME" >/dev/null 2>&1 || true
[ "${1:-}" = down ] && { echo "$NAME removed"; exit 0; }
CONF="$HOME/.colima/modu-ports.nginx.conf"   # VM 에는 $HOME 만 마운트돼 있어 /var/folders 의 mktemp 는 못 쓴다
{ echo "events {}"; echo "stream {"; for p in $PORTS; do echo "  server { listen $p; proxy_pass $VM_IP:$p; proxy_connect_timeout 3s; }"; done; echo "}"; } > "$CONF"
args=(); for p in $PORTS; do args+=(-p "$p:$p"); done
docker run -d --name "$NAME" --restart unless-stopped "${args[@]}" -v "$CONF:/etc/nginx/nginx.conf:ro" nginx:1.27-alpine >/dev/null
echo "$NAME up → $VM_IP, ports: $PORTS"
