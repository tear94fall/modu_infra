#!/bin/sh
# Rollout 의 카나리 단계를 파드 수에서 만든다(2026-11-15). 규칙은 사람이 정한 것(docs 2026-11-15 카나리 설계):
#   파드 N 개 → 단계 k=1..N-1, 가중치 floor(100k/N) (2개: 50 → 100, 3개: 33 → 66 → 100, 10개: 10 → 20 → … → 100). 각 단계 뒤 무기한 일시정지(pause: {}).
#   파드 1개가 5% 미만이면(N > 20) p=ceil(N/20) 개씩 묶는다(k = p, 2p, … < N). N ≤ 1 → 단계 없음(steps: []) = 지금의 롤링과 같다.
# 비율은 파드 수 비율이다(트래픽 라우터 없음): Argo Rollouts 는 setWeight W 에서 canary 파드 수를 ceil(W·N/100) 으로 잡고, floor(100k/N) 이 정확히 k 개가 되게 한다.
#
#   sh k8s/rollouts/steps.sh <N>          # strategy.canary 아래에 붙일 `steps:` 블록을 찍는다(들여쓰기 6칸 = Rollout 매니페스트의 strategy.canary 아래)
#   예) sh k8s/rollouts/steps.sh 2
#         steps:
#           - setWeight: 50
#           - pause: {}
# 매니페스트에 적은 뒤 sh k8s/rollouts/check.sh 로 replicas 와 어긋나지 않는지 확인한다(런타임 계산은 없다 — git 이 진실).
set -eu
N=${1:?사용: steps.sh <replicas>}
IND=${IND:-"      "}
if [ "$N" -le 1 ]; then echo "${IND}steps: []"; exit 0; fi
P=$(( (N + 19) / 20 ))
echo "${IND}steps:"
k=$P
while [ "$k" -lt "$N" ]; do
  echo "${IND}  - setWeight: $(( 100 * k / N ))"
  echo "${IND}  - pause: {}"
  k=$(( k + P ))
done
