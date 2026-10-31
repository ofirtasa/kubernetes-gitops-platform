# 0007. Secrets from AWS Secrets Manager through External Secrets Operator

- Status: accepted
- Date: 2026-10-31

## Context

`/nodes` is protected by an API key, with a different key per environment. The repository is
public and Git must never contain a secret, and Terraform state should not hold one either.

## Decision

**Flow:**

```
Secrets Manager                 ESO (Pod Identity role)            Kubernetes
k8s-gitops/<env>/nodes-api  →   assumes k8s-gitops-secrets-<env> → Secret nodes-api → file in the pod
```

- **Secrets Manager** holds one secret per environment, created by Terraform.
  - The key is generated during `terraform apply` (`ephemeral "random_password"`) and sent
    write-only (`secret_string_wo`), so it never appears in state or in the plan.
  - Rotation: increase `secret_string_wo_version` and apply.
- **External Secrets Operator** runs in its own namespace, deployed by Argo CD.
  - Its Pod Identity role can do one thing: assume the three per-environment roles.
  - Each environment role can read only its own secret.
- **SecretStore per namespace, owned by the platform:** each store names its environment's
  role. The `nodes-api` AppProject may not create SecretStores, so a workload cannot point
  its store at another environment's role and read its secret.
  - Cluster-wide stores (ClusterSecretStore) and PushSecret are turned off in ESO.
- **ExternalSecret in the chart:** the application decides which remote key maps to which
  Secret key. ESO creates and owns the `nodes-api` Secret.
- **Mounted as a file, read on every request:** a rotated key reaches the pods within
  `refreshInterval` (1h) plus the kubelet sync (about a minute), with no restart.

## Consequences

- The cluster depends on Secrets Manager only when a key changes. If ESO or AWS is
  unavailable, the existing Secret keeps working.
- To call `/nodes`, read the key from Secrets Manager:

  ```bash
  aws secretsmanager get-secret-value --secret-id k8s-gitops/prod/nodes-api \
    --query SecretString --output text
  curl -H "X-API-Key: <api_key>" http://<alb-dns>/nodes
  ```

- The secrets use the AWS managed key (`aws/secretsmanager`), which Trivy reports as LOW
  (AWS-0098).
- `recovery_window_in_days = 0` deletes the secrets immediately on destroy, so the
  environment can be rebuilt with the same names.

## Production differences

- A customer managed KMS key per environment, with a key policy that limits decryption to
  the matching role.
- Automatic rotation with a rotation Lambda, instead of a version bump in Terraform.
- A recovery window, so a deleted secret can be restored.
- Separate AWS accounts per environment (see ADR 0003): the account boundary, not only the
  role, keeps dev away from production secrets.
