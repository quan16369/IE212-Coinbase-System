{{- define "bento-price-predictor.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "bento-price-predictor.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "bento-price-predictor.labels" -}}
app.kubernetes.io/name: {{ include "bento-price-predictor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "bento-price-predictor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "bento-price-predictor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
