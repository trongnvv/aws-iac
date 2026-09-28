{{- define "app.name" -}}
{{- default .Release.Name .Values.nameOverride -}}
{{- end -}}

{{- define "app.labels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $k, $v := .Values.labels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}

{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
{{- end -}}
