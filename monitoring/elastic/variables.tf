variable "kibana_url" {
  description = "Kibana endpoint, for example https://<deployment>.kb.<region>.aws.elastic.cloud"
  type        = string
}

variable "kibana_api_key" {
  description = "Kibana API key with privileges to manage data views, connectors and rules"
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Incoming webhook of the alerts channel. Sent write-only, never stored in state"
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "environments" {
  description = "Namespaces the rules watch"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}
