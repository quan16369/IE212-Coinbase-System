{{- define "alert-rule-engine.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "alert-rule-engine.fullname" -}}
{{- default (include "alert-rule-engine.name" .) .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "alert-rule-engine.labels" -}}
app.kubernetes.io/name: {{ include "alert-rule-engine.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "alert-rule-engine.selectorLabels" -}}
app.kubernetes.io/name: {{ include "alert-rule-engine.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
