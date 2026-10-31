# GitOps and delivery

How a code change reaches dev, staging and prod, and how the cluster stays equal to Git.
Diagrams: [architecture.md](architecture.md#delivery). Decisions: ADR
[0002](decisions/0002-argo-cd-for-gitops.md) and [0005](decisions/0005-promotion-and-ci-write-back.md).

## Repository structure

| Path | Owner | Content |
|---|---|---|
| `argocd/bootstrap/` | Terraform creates the root Application that points here | AppProjects and the `platform` and `apps` Applications |
| `argocd/platform/` | Argo CD | Namespaces, add-ons (Helm charts from their upstream repos), SecretStores, policies |
| `argocd/apps/` | Argo CD | One ApplicationSet: `nodes-api` × dev, staging, prod |
| `charts/nodes-api/` | Developers | How the service is deployed; the same for every environment |
| `environments/values-<env>.yaml` | CI (dev) and promotion PRs (staging, prod) | What differs per environment: image tag, replicas, log level, listener port, secret name |

## CI pipeline

Workflows in `.github/workflows/`. Every PR runs all of them; `main` requires the checks.

| Workflow | Jobs |
|---|---|
| `app.yml` | `test` (ruff, pytest), `dockerfile-lint` (hadolint), `image` (build, Trivy scan, push to ECR on `main` only), `promote-dev` |
| `chart.yml` | Render the chart for each environment, kubeconform (schemas), kube-linter, Kyverno tests and policies against the rendered chart |
| `terraform.yml` | `fmt`, `validate` per stack, Trivy IaC scan |

- **Build, test, scan, push:** tests and lint first; the image is built once, scanned by
  Trivy (fails on fixable HIGH or CRITICAL), and pushed only from `main`.
- **AWS access:** GitHub OIDC. The role trusts only `main` of this repository and can push
  to one ECR repository. There are no AWS keys in GitHub.
- **No deployment from CI.** The only write CI does is a Git commit of the dev image tag.

## Image tagging

- The tag is the full commit SHA. It is unique, traceable to the exact code, and never reused.
- ECR tags are immutable, so a tag always means the same image.
- No `latest`: a Kyverno policy rejects it in the cluster.
- The lifecycle policy keeps the last 30 images, enough to roll back.

## Promotion

| Environment | Trigger | Approval |
|---|---|---|
| dev | Merge to `main` → CI commits the new SHA to `values-dev.yaml` | The code PR review |
| staging | PR copying the dev tag to `values-staging.yaml` | PR approval |
| prod | PR copying the staging tag to `values-prod.yaml` | PR approval |

The same image moves through all three environments; nothing is rebuilt.

## Deployment update strategy

- **RollingUpdate** with `maxSurge: 1`, `maxUnavailable: 0`: a new pod must be Ready before an
  old one is removed.
- **Readiness** on `/ready`, plus ALB **pod readiness gates**: a pod counts as Ready only
  after the ALB reports it healthy.
- **Graceful shutdown:** a 10-second `preStop` sleep lets the ALB stop sending traffic before
  the process exits.
- **PDB** `maxUnavailable: 1` and **topology spread** across AZs protect capacity during node
  drains.
- Policy failures stop the rollout before it starts: Kyverno rejects the Deployment and Argo
  CD shows the message.

## Rollback

1. `git revert` the promotion commit. Argo CD syncs the previous tag within minutes; the image
   is still in ECR.
2. In an emergency, roll back in the Argo CD UI to a previous sync. Automated sync must be
   paused for that Application first, otherwise self-heal returns it to Git; the revert
   commit follows, so Git stays the source of truth.

## Reconciliation and drift

**Argo CD (used here):**
- Every 3 minutes, and on every refresh, it renders the desired state from Git and compares
  it with the live objects (server-side diff).
- `automated` sync applies any difference. `selfHeal` reverts manual changes in the cluster,
  for example a `kubectl scale` or `kubectl edit`. `prune` deletes objects removed from Git.
- Exceptions are explicit:
  - `ignoreDifferences` for fields that controllers own at runtime (webhook CA bundles).
  - The chart leaves `replicas` out of the Deployment when the HPA is enabled, so Argo CD
    and the HPA never fight over it.
  - Namespaces are never pruned (`Prune=false`).
- The UI shows each Application as Synced or OutOfSync and Healthy or Degraded. The monitoring
  design alerts when an Application stays unhealthy or out of sync.

**Flux (the equivalent):**
- The `source-controller` fetches the Git repository on an interval. The `kustomize-controller`
  and `helm-controller` apply it, each on its own `interval`.
- Every reconciliation re-applies the desired state with server-side apply, so drift is
  corrected on the next interval. There is no separate self-heal switch.
- `prune: true` on a Kustomization deletes removed objects. `suspend: true` pauses
  reconciliation during an incident, like turning off automated sync in Argo CD.
- Flux has no built-in UI. Status is read with `flux get` and from the CRDs' conditions.
