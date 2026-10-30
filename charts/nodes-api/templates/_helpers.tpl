{{- define "nodes-api.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "nodes-api.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "nodes-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nodes-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "nodes-api.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{ include "nodes-api.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | trunc 12 | quote }}
app.kubernetes.io/part-of: k8s-gitops
app.kubernetes.io/managed-by: {{ .Release.Service }}
environment: {{ .Values.config.appEnv | quote }}
{{- end }}

{{/* Cluster-scoped objects are shared by all environments, so their names include the namespace. */}}
{{- define "nodes-api.clusterName" -}}
{{- printf "%s-%s" .Release.Namespace (include "nodes-api.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
