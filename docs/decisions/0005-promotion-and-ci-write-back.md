# 0005. Promotion between environments and CI write-back to Git

- Status: accepted
- Date: 2026-10-30

## Context

The assignment requires a promotion strategy across dev, staging and prod, and CI/CD must not
deploy to the cluster directly.

**The original intent:** every change to `main` goes through a pull request with all required
checks passing, without exceptions.
- `main` was protected by a branch protection rule: PR required, force push and deletion
  blocked, CI checks required.
- CI was meant to have read-only access to the repository.

**The conflict:** continuous delivery to dev means CI must write the new image tag to Git after
every merge.
- A pull request opened with the workflow's `GITHUB_TOKEN` does not trigger workflows (GitHub
  prevents loops this way). So its required checks never report, and it can never be merged.
- A bypass for the built-in GitHub Actions app is allowed only on organization repositories,
  and this is a personal repository.

## Decision

**Promotion model (build once, promote the same image):**

| Environment | How a version gets there | Approval |
|---|---|---|
| dev | CI commits the new tag to `environments/values-dev.yaml` after every merge to `main` | The merge of the code PR |
| staging | PR that copies the dev tag into `values-staging.yaml` | PR approval |
| prod | PR that copies the staging tag into `values-prod.yaml` | PR approval |

- The image is built once, tagged with the commit SHA and never rebuilt for another
  environment. What reaches prod is byte-for-byte what was tested in staging.
- Argo CD detects the changed values file and deploys it. No pipeline talks to the cluster.
- **Rollback** is `git revert` of the promotion commit. Argo CD returns the previous tag. The
  image still exists, because ECR tags are immutable and the lifecycle policy keeps the last 30.

**The exception for CI write-back:**
- `main` is protected by a repository **ruleset** with the same rules as before: PR
  required, the 7 CI checks required, no force push, no deletion.
- **One bypass actor:** the GitHub App `k8s-gitops-ci-ofirtasa`.
  - Its only permission is Contents read/write, and it is installed only on this repository.
  - The `promote-dev` job takes a token from it that is valid for one hour and is revoked when
    the job ends.
  - It commits only the dev tag. The commit is attributed to the App's bot user, so history
    shows exactly what CI changed.
- The App's private key is stored in GitHub Secrets. Its client ID is stored as a repository
  variable.

## Consequences

- Everything except the dev tag still follows the original rule: a PR with passing checks.
- The App can technically push any file to `main`. This is limited by process, not by
  configuration:
  - Only workflows hold its key, and workflows change only through reviewed PRs.
  - The workflow modifies one file only.
- The bypass commit does not run the checks. It changes one value in one file, and the
  `chart` workflow still renders the chart for it after the push.

## Production differences

- **Organization repository:** the ruleset can restrict the App's bypass more precisely, for
  example with push rules limited to `environments/**`.
- **Separate config repository:** environment values live there, so the application
  repository needs no write-back exception at all.
- **Alternatives to CI write-back:**
  - Argo CD Image Updater.
  - Promotion tooling (for example Kargo) that opens the staging and prod PRs automatically.
