# 0001. Single repository, chart separated from environment values

- Status: accepted
- Date: 2026-10-30

## Context

The assignment asks for one Git repository containing the application, its Kubernetes
packaging, the GitOps configuration for three environments, infrastructure as code and
documentation. We need a layout that keeps these concerns readable and makes environment
promotion easy to review.

## Decision

- One repository with a top-level folder per concern: `app/`, `charts/`, `environments/`,
  `argocd/`, `infra/`, `policies/`, `monitoring/`, `docs/`.
- The Helm chart (`charts/nodes-api`) describes *how* the service is deployed and is the same
  for every environment. What differs per environment lives in
  `environments/values-<env>.yaml`, referenced from Argo CD via `valueFiles`.
- Terraform is split into `bootstrap` (the S3 state bucket: first applied with local state, which is then migrated into the bucket)
  and `platform` (everything else).

## Consequences

- A promotion is a change to one `environments/values-<env>.yaml` file, so the diff of a
  promotion PR shows exactly which version reached which environment. Rollback is a
  `git revert` of that change.
- CI writes image tags only to environment files; the chart changes only when the deployment
  shape changes.

## Trade-offs

In production, application code and deployment configuration are usually kept in separate
repositories, so that CI needs write access only to the config repository and code
contributors cannot change production configuration. A single repository is chosen here
because the assignment requires one, and it keeps the whole flow visible in one place.
