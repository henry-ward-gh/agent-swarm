{{- define "swarm.name" -}}
{{- .Values.global.swarm | default .Release.Name -}}
{{- end -}}

{{- define "swarm.brokerLabels" -}}
agent-swarm.io/swarm: {{ include "swarm.name" . | quote }}
agent-swarm.io/component: broker
app.kubernetes.io/name: valkey
app.kubernetes.io/part-of: agent-swarm
{{- end -}}

{{- /* IPv4 dotted quad -> integer, for the Service CIDR check below. */ -}}
{{- define "swarm.ipInt" -}}
{{- $o := splitList "." . -}}
{{- if ne (len $o) 4 -}}{{- fail (printf "not an IPv4 address: %q" .) -}}{{- end -}}
{{- add (mul (int64 (index $o 0)) 16777216) (mul (int64 (index $o 1)) 65536) (mul (int64 (index $o 2)) 256) (int64 (index $o 3)) -}}
{{- end -}}

{{- /* Fails the render unless dict "ip" lies inside dict "cidr" (ADR 0003: pinned IPs must be Service IPs). */ -}}
{{- define "swarm.assertInCIDR" -}}
{{- $parts := splitList "/" .cidr -}}
{{- $base := int64 (include "swarm.ipInt" (index $parts 0)) -}}
{{- $size := int64 1 -}}
{{- range until (int (sub 32 (int (index $parts 1)))) -}}{{- $size = mul $size 2 -}}{{- end -}}
{{- $ip := int64 (include "swarm.ipInt" .ip) -}}
{{- if or (lt $ip $base) (ge $ip (add $base $size)) -}}
{{- fail (printf "pinned IP %s is outside the Service CIDR %s" .ip .cidr) -}}
{{- end -}}
{{- end -}}

{{- /*
  The egress allowlist as a JSON array of IPs: the broker's pinned ClusterIP plus every
  Approved Destination the Agents declare ("ip:port"). tcp_connect matching pairs no port
  with an address, so only the IP is enforced; each Approved Destination has its own pinned IP.
*/ -}}
{{- define "swarm.egressIPs" -}}
{{- if not .Values.broker.clusterIP -}}
{{- fail "guardrails.enabled needs broker.clusterIP pinned, or the egress Guardrail would kill the Agents' own broker traffic (ADR 0003)" -}}
{{- end -}}
{{- $entries := list (printf "%s:%v" .Values.broker.clusterIP .Values.broker.port) -}}
{{- $entries = concat $entries ((.Values.orchestrator.egress | default dict).allow | default list) ((.Values.worker.egress | default dict).allow | default list) -}}
{{- $ips := list -}}
{{- range $entries -}}
{{- $ip := index (splitList ":" .) 0 -}}
{{- include "swarm.assertInCIDR" (dict "ip" $ip "cidr" $.Values.guardrails.serviceCIDR) -}}
{{- $ips = append $ips $ip -}}
{{- end -}}
{{- $ips | uniq | sortAlpha | toJson -}}
{{- end -}}

{{- /* Guardrails guard every Agent of this Swarm (Orchestrator and Workers) and never the broker, which has no role label. */ -}}
{{- define "swarm.guardrailSelector" -}}
matchLabels:
  agent-swarm.io/swarm: {{ include "swarm.name" . | quote }}
matchExpressions:
  - key: agent-swarm.io/role
    operator: Exists
{{- end -}}
