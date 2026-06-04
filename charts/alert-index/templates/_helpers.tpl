{{- define "alert-index.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "alert-index.fullname" -}}
{{- default (include "alert-index.name" .) .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "alert-index.labels" -}}
app.kubernetes.io/name: {{ include "alert-index.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "alert-index.selectorLabels" -}}
app.kubernetes.io/name: {{ include "alert-index.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
