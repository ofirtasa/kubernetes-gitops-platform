# 0002. Argo CD as the GitOps controller

- Status: accepted
- Date: 2026-10-30

## Context

The assignment requires Flux or Argo CD as the GitOps model; CI/CD must not deploy to the
cluster directly. Both are CNCF graduated projects that reconcile cluster state from Git.

## Decision

Use Argo CD.

- **Visibility:** the UI shows sync status, health and the live-vs-desired diff per
  environment, which helps both day-to-day operations and incident investigation.
- **Environment fan-out:** one `ApplicationSet` generates the dev, staging and prod
  Applications from a single definition.
- **Ordering:** sync waves let platform add-ons (CRDs, controllers) come up before the
  workloads that depend on them.
- **Team experience:** the team already operates Argo CD, which lowers operational risk.

## Consequences

- Argo CD is installed once by Terraform together with the root Application. This is the
  only step that touches the cluster from outside Git (the bootstrap exception); after it,
  Argo CD manages all add-ons and workloads, including itself.
- Automated sync with `selfHeal` and `prune` is enabled, so manual changes in the cluster
  are reverted and resources removed from Git are deleted.

## Trade-offs

- Flux is lighter (no UI, no Redis) and is configured entirely through Kubernetes CRDs.
- Flux ships image automation controllers that can commit new image tags to Git. Argo CD
  has no built-in equivalent. Here CI commits the new tag to the dev values file instead,
  which keeps every deployment change an explicit, reviewable Git commit.
