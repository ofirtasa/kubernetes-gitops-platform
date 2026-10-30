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

- **Bootstrap exception:** Terraform installs Argo CD and the root Application. This is the
  only step that touches the cluster from outside Git.
- **Ownership:** Terraform remains the owner of Argo CD itself (chart version and values in
  `terraform.tfvars`). Argo CD manages every add-on and workload.
  - Argo CD does not manage itself. Otherwise Terraform and Argo CD would both own the same
    resources and keep overwriting each other.
- **App of apps:** the root Application (`argocd/bootstrap`) creates the AppProjects, then
  the `platform` Application (namespaces, add-ons), then the `apps` Application (the
  nodes-api ApplicationSet). The sync waves are -2, -1 and 0.
  - A health check for `Application` resources (in `argocd-cm`) makes each wave wait until
    the previous one is healthy.
- **AppProjects:** `platform` may install cluster-wide objects. `nodes-api` may deploy only
  to the dev, staging and prod namespaces. Its only cluster-wide objects are the node-read
  ClusterRole and its binding.
- **Automated sync:** `selfHeal` and `prune` are enabled. Manual changes in the cluster are
  reverted, and resources removed from Git are deleted.
- **Namespaces are never pruned** (`Prune=false`). Removing a file must not delete an
  environment and everything in it.
- **Access:** the UI is reached through `kubectl port-forward` with the local admin user.
  There is no domain or SSO; the bundled Dex server is disabled.

## Trade-offs

- Flux is lighter (no UI, no Redis) and is configured entirely through Kubernetes CRDs.
- Flux ships image automation controllers that can commit new image tags to Git. Argo CD
  has no built-in equivalent. Here CI commits the new tag to the dev values file instead,
  which keeps every deployment change an explicit, reviewable Git commit.
