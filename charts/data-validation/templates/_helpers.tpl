{{- define "data-validation.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "data-validation.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "data-validation.labels" -}}
app.kubernetes.io/name: {{ include "data-validation.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "data-validation.selectorLabels" -}}
app.kubernetes.io/name: {{ include "data-validation.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
