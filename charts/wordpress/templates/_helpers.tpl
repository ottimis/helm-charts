{{- define "wordpress.name" -}}
{{- default .Chart.Name .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Define helper for retrieving WordPress URL.
*/}}
{{- define "wordpress.url" -}}
{{- $url := default "http://localhost" .Values.wordpress.hostname -}}
{{/* Use default WordPress URL if not specified */}}
{{- if and (not .Values.wordpress.hostname) (and .Values.ingress.enabled .Values.ingress.hosts) -}}
{{/* Check if ingress is enabled and hosts are defined */}}
{{- $host := index .Values.ingress.hosts 0 -}} {{/* Get the first host */}}
{{- $protocol := "http://" -}} {{/* Default protocol */}}
{{- if or (hasPrefix "http://" $host) (hasPrefix "https://" $host) -}} {{/* Check if protocol is already included */}}
{{- $url = $host -}} {{/* Use the host as is if it includes protocol */}}
{{- else -}}
{{- $url = printf "%s%s" $protocol $host -}} {{/* Prefix the protocol if not included */}}
{{- end -}}
{{- end -}}
{{- $url -}} {{/* Return the URL */}}
{{- end -}}