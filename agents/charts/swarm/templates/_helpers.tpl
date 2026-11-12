{{- define "swarm.name" -}}
{{- .Values.global.swarm | default .Release.Name -}}
{{- end -}}

{{- define "swarm.brokerLabels" -}}
agent-swarm.io/swarm: {{ include "swarm.name" . | quote }}
agent-swarm.io/component: broker
app.kubernetes.io/name: valkey
app.kubernetes.io/part-of: agent-swarm
{{- end -}}
