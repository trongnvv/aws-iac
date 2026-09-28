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

{{- /* Resolved Service/backend port: port.servicePort, or port.number when 0. */ -}}
{{- define "app.servicePort" -}}
{{- .Values.port.servicePort | default .Values.port.number -}}
{{- end -}}

{{- /* Auto health probe derived from `port`: gRPC probe when appProtocol=grpc, else httpGet. */ -}}
{{- define "app.probe" -}}
{{- $p := .Values.port -}}
{{- if eq ($p.appProtocol | toString) "grpc" -}}
grpc:
  port: {{ $p.number }}
{{- else -}}
httpGet:
  path: {{ $p.healthPath | default "/healthz" }}
  port: {{ $p.name }}
{{- end -}}
{{- end -}}
