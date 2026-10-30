output "cluster_name" {
  value = module.eks.cluster_name
}

output "region" {
  value = var.region
}

output "ecr_repository_url" {
  value = aws_ecr_repository.nodes_api.repository_url
}

output "github_actions_role_arn" {
  description = "Role assumed by the CI workflow to push images."
  value       = aws_iam_role.github_actions_ecr_push.arn
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "argocd_ui" {
  description = "Open the Argo CD UI on https://localhost:8080 (user admin)."
  value       = "kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443"
}
