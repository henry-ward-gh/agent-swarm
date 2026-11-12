{{- define "agent.swarm" -}}
{{- .Values.global.swarm | default .Release.Name -}}
{{- end -}}

{{- define "agent.fullname" -}}
{{- printf "%s-%s" (include "agent.swarm" .) .Values.role | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "agent.selectorLabels" -}}
agent-swarm.io/swarm: {{ include "agent.swarm" . | quote }}
agent-swarm.io/role: {{ .Values.role | quote }}
{{- end -}}

{{- define "agent.labels" -}}
{{ include "agent.selectorLabels" . }}
agent-swarm.io/implementation: {{ .Values.implementation | quote }}
app.kubernetes.io/name: agent
app.kubernetes.io/instance: {{ include "agent.fullname" . }}
app.kubernetes.io/part-of: agent-swarm
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "agent.image" -}}
{{- $repo := .Values.image.repository | default .Values.global.image.repository -}}
{{- $tag := .Values.image.tag | default .Values.global.image.tag -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
