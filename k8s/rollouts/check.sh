#!/bin/sh
# 렌더된 dev 오버레이의 모든 Rollout 에 대해 strategy.canary.steps 가 steps.sh 규칙(파드 수 기준)과 같은지 검사한다. 어긋나면 이름을 찍고 exit 1.
# modu_infra 에는 CI 가 없으므로 Rollout 이나 replicas 를 바꾼 PR 전에 손으로 돌린다(README). 렌더에 PyYAML 이 없어도 되게 kubectl 의 JSON 변환을 쓴다
# (client-side dry-run — Rollout CRD 가 클러스터에 있어야 한다).
#
#   sh k8s/rollouts/check.sh [overlay-dir]      (기본 k8s/overlays/dev)
set -eu
cd "$(dirname "$0")/.."
OVERLAY=${1:-overlays/dev}
kubectl kustomize "$OVERLAY" | kubectl apply --dry-run=client -o json -f - | python3 -c '
import sys, json, subprocess, os
dec = json.JSONDecoder(); buf = sys.stdin.read(); i = 0; objs = []
while i < len(buf):
    while i < len(buf) and buf[i].isspace(): i += 1
    if i >= len(buf): break
    o, j = dec.raw_decode(buf, i); i = j
    objs.extend(o.get("items", [])) if o.get("kind") == "List" else objs.append(o)   # kubectl 은 여러 객체를 kind: List 로 묶어 낸다
bad = 0; total = 0
for o in objs:
    if o.get("kind") != "Rollout": continue
    total += 1
    name = o["metadata"]["name"]; spec = o.get("spec", {})
    n = int(spec.get("replicas", 1))
    steps = ((spec.get("strategy") or {}).get("canary") or {}).get("steps") or []
    want = subprocess.run(["sh", "rollouts/steps.sh", str(n)], capture_output=True, text=True, env={**os.environ, "IND": ""}).stdout
    # steps.sh 출력을 같은 구조로
    exp = []
    for line in want.splitlines()[1:]:
        line = line.strip().lstrip("- ")
        if line.startswith("setWeight:"): exp.append({"setWeight": int(line.split(":")[1])})
        elif line.startswith("pause:"): exp.append({"pause": {}})
    if steps != exp:
        bad += 1; print(f"MISMATCH {name}: replicas={n} steps={steps} expected={exp}")
print("checked %d rollouts, %d mismatch" % (total, bad))
sys.exit(1 if bad else 0)
'
