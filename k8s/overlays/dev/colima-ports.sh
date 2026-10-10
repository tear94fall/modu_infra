#!/usr/bin/env bash
# Colima(k3s)에서 LoadBalancer 포트를 Mac 으로 내보낸다(2026-10-06). k3s 의 ServiceLB 는 VM 안 iptables 로 포트를 여는데 Lima 의 포트 포워딩은
# "소켓으로 듣는 포트"만 Mac 으로 넘기므로 LB 포트가 Mac 에 안 보인다. 그래서 VM 의 docker 로 nginx(stream) 컨테이너를 띄워 각 포트를 VM IP 의
# 같은 포트로 넘기고(-p 로 docker-proxy 가 0.0.0.0 으로 듣는다 → Lima 가 Mac 의 모든 인터페이스로 포워딩), 결과적으로 localhost·192.168.0.x 에서
# compose/Docker Desktop 시절과 같은 주소가 된다(안드로이드 앱의 192.168.0.3:8000 도 그대로).
#   ./colima-ports.sh            # (재)생성. colima 를 다시 만들었거나 포트를 추가했을 때 다시 돌린다 — restart=unless-stopped 라 재부팅엔 살아난다.
#   ./colima-ports.sh down
set -euo pipefail
NAME=modu-ports
# LAN(폰)에 열어야 하는 포트. 안드로이드 앱이 192.168.0.x 로 직접 붙는다 — 채팅·커머스 API 는 8000, 커머스 WebView 는 8082.
PUBLIC_PORTS="8000 8082"
# 맥에서만 쓰는 포트(브라우저·확인 도구). VM 의 127.0.0.1 에만 열면 Lima 가 맥의 127.0.0.1 로만 넘긴다
# (lima.yaml 의 0.0.0.0 규칙은 guestIPMustBeZero 라 루프백 리스너에는 안 맞고, 127.0.0.1→127.0.0.1 규칙이 걸린다).
# 콘솔3(8081·8084·8085) config(8888) OpenSearch(9200·5601) Grafana(3000) Prometheus(19090) kafka-ui(9009) RabbitMQ(15672) Argo(8090) RGW(7480) Ceph대시보드(7001)
LOCAL_PORTS="8081 8084 8085 8888 5601 9200 3000 19090 9009 15672 8090 7480 7001"
PORTS="$PUBLIC_PORTS $LOCAL_PORTS"
# colima 버전에 따라 키 이름이 다르다(예전 ip_address → 지금 address). 둘 다 보고, 그래도 없으면 VM 안에서 직접 읽는다.
VM_IP=${VM_IP:-$(colima ls --json 2>/dev/null | python3 -c 'import sys,json
d=json.load(sys.stdin)
print(d.get("address") or d.get("ip_address") or "")' 2>/dev/null)}
[ -n "$VM_IP" ] || VM_IP=$(colima ssh -- ip -4 -o addr show col0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
[ -n "$VM_IP" ] || { echo "VM IP 를 알아내지 못했다. VM_IP=192.168.64.3 처럼 직접 넘겨라." >&2; exit 1; }
docker rm -f "$NAME" >/dev/null 2>&1 || true
[ "${1:-}" = down ] && { echo "$NAME removed"; exit 0; }
CONF="$HOME/.colima/modu-ports.nginx.conf"   # VM 에는 $HOME 만 마운트돼 있어 /var/folders 의 mktemp 는 못 쓴다
{ echo "events {}"; echo "stream {"; for p in $PORTS; do echo "  server { listen $p; proxy_pass $VM_IP:$p; proxy_connect_timeout 3s; }"; done; echo "}"; } > "$CONF"
args=()
for p in $PUBLIC_PORTS; do args+=(-p "$p:$p"); done              # 0.0.0.0 — 폰에서 보인다
for p in $LOCAL_PORTS;  do args+=(-p "127.0.0.1:$p:$p"); done    # VM 루프백 — 맥에서만 보인다
docker run -d --name "$NAME" --restart unless-stopped "${args[@]}" -v "$CONF:/etc/nginx/nginx.conf:ro" nginx:1.27-alpine >/dev/null
echo "$NAME up → $VM_IP"
echo "  LAN(0.0.0.0): $PUBLIC_PORTS"
echo "  맥 전용(127.0.0.1): $LOCAL_PORTS"
