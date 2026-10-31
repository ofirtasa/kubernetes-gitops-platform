# 0008. Policy-as-code with Kyverno

- Status: accepted
- Date: 2026-10-31

## Context

The chart already follows good practices, but nothing stops the next change, or a manual
`kubectl apply`, from deploying an image from Docker Hub, a `latest` tag, or a pod without
resources or probes. The rules should be enforced by the cluster and checked in CI, not only
by review.

## Decision

**Layers, each catching a different class of problem:**

| Layer | Where | What it checks |
|---|---|---|
| kube-linter, kubeconform | CI, on the rendered chart | Schema and best-practice lint, before merge |
| Kyverno CLI | CI | Policy unit tests, and the rendered chart against the same policies the cluster enforces |
| Pod Security Admission `restricted` | Cluster, per namespace | Security context: non-root, no privilege escalation, dropped capabilities, seccomp |
| Kyverno admission | Cluster | Rules PSA does not cover (below) |

**Policies** (`policies/`), enforced (`Deny`) in namespaces labelled `environment`:

| Policy | Rule | Why |
|---|---|---|
| `restrict-image-registries` | Images only from this project's ECR | Every image was built by CI, scanned by Trivy, and stored with an immutable tag |
| `disallow-latest-tag` | Explicit tag or digest, never `latest` | Git always states the exact version; rollback returns the previous one |
| `require-requests-limits` | CPU and memory requests, memory limit | Scheduler, HPA and Cluster Autoscaler depend on requests; the limit protects nodes shared by three environments |
| `require-probes` | Readiness and liveness probes | Safe rolling updates and recovery from a hung process |

- **`ValidatingPolicy` (CEL),** the current Kyverno API. `ClusterPolicy` is deprecated in
  Kyverno 1.19.
- **Autogen** applies each rule to Deployments and other controllers as well as Pods, so a
  violation fails the Argo CD sync with a clear message, instead of a ReplicaSet that
  silently cannot create pods.
- **Platform add-ons are out of scope:** they run third-party images from public
  registries, and their namespaces carry no `environment` label.
- **Tests:** `policies/tests` holds one compliant Deployment and one that breaks each policy.
  `kyverno test` proves each policy blocks what it should and nothing else.
- **Availability:** the admission webhook fails closed, so the admission controller runs two
  replicas with a PDB. Background, cleanup and reports controllers run one replica each.

## Consequences

- A change that breaks a policy fails in CI before merge. If it reaches the cluster anyway,
  the admission webhook rejects it and Argo CD shows the policy message.
- If Kyverno is down, no new pod can start in dev, staging or prod. Pods that already run
  are not affected.
- A new registry or exception is a reviewed change to `policies/`.

## Production differences

- Image signature verification (`ImageValidatingPolicy` with Cosign or AWS Signer), so only
  images signed by CI can run, not only images from the right registry.
- Three admission replicas spread across AZs.
- New policies start in `Audit` and move to `Deny` after the policy reports show no
  violations.
- PolicyExceptions with an owner and an expiry date instead of editing a policy.
