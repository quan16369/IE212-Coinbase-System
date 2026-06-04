{{- define "feature-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "feature-platform.fullname" -}}
{{- default (include "feature-platform.name" .) .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "feature-platform.labels" -}}
app.kubernetes.io/name: {{ include "feature-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "feature-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "feature-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
