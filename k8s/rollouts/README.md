# Rollouts — 카나리 배포 (2026-11-15)

앱 Deployment 18개(배포 탭의 서비스 전부)는 **같은 이름의 Rollout**(Argo Rollouts, `workloadRef`)이 파드를 가진다. Deployment 는 파드 템플릿(이미지 태그·env·프로브)만 담고
`replicas: 0` 이다. 배포 탭이 Deployment 의 이미지 태그를 바꾸면(kustomize `images:` + Argo Sync) 컨트롤러가 새 ReplicaSet 을 띄운다 — 배포 흐름은 그대로다.

- 컨트롤러: `k8s/cicd/argo-rollouts`(v1.10.2, 네임스페이스 argo-rollouts, Argo CD Application `modu-rollouts`). 대시보드·kubectl 플러그인은 없다.
- 단계(steps)는 **파드 수에서 만든다**: `sh k8s/rollouts/steps.sh <N>` → 매니페스트에 붙인다. 파드 1개 = 단계 없음(지금의 롤링과 같음), N개 = k/N 비율(`floor(100k/N)`, 5% 미만이면 묶음), 각 단계 뒤 무기한 일시정지.
  dev 는 point-service 만 2(오버레이 패치). 기본 base 는 전부 1(config·gateway 는 2 — dev 오버레이가 1 로 내리며 steps 도 비운다).
- **검사**: `sh k8s/rollouts/check.sh` — 렌더된 dev 오버레이의 모든 Rollout 에 대해 steps 가 replicas 규칙과 같은지. Rollout·replicas 를 바꾼 PR 전에 손으로 돌린다(modu_infra 엔 CI 가 없다).
- **진행/중단**은 모두 시스템 배포 탭(deploy-service 가 Rollout status 를 패치: promote `pauseConditions: null`, promoteFull, abort). 콘솔 없이 급할 때:
  `kubectl -n modu patch rollout <svc> --subresource=status --type=merge -p '{"status":{"pauseConditions":null}}'`(진행) / `-p '{"status":{"abort":true}}'`(중단).
- **템플릿 변경은 배포 탭을 거친다.** 배포 탭 밖에서 Deployment 템플릿을 바꾸면(전체 Argo Sync, `kubectl set env` …) 파드 2개 이상 서비스는 첫 단계에서 멈추고 **배포 기록이 없다** —
  서비스 표가 "멈춤(배포 기록 없음)" 으로 보여 주고 서비스 행의 진행/중단으로 푼다(git 은 사람이 되돌린다).
- 전환 기록(2026-11-15 dev): 컨트롤러 → Rollout 을 서비스 2~3개씩 apply(Rollout 이 새 RS 를 띄우고 Healthy 가 되면 `scaleDown: onsuccess` 가 Deployment 를 0 으로). 서비스마다 파드 1회 교체.
  **Rollout 객체만** apply 해야 Deployment 의 현재 이미지(local-* 등)가 git 태그로 되돌아가지 않는다.
