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

{{/*
Define helper for managing WordPress Password.
*/}}
{{- define "wordpress.secretName" -}}
{{- $name := include "wordpress.name" . -}}
{{- printf "%s-admin-password" $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "wordpress.password" -}}
{{- $secretName := include "wordpress.secretName" . -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace $secretName -}}
{{- if and $secret (hasKey $secret.data "password") -}}
  {{- $password := $secret.data.password -}}
  {{- printf "%s" $password -}}
{{- else -}}
  {{- $password := randAlphaNum 12 | b64enc -}}
  {{- $password | quote -}}
{{- end -}}
{{- end -}}

{{/*
Define helper for managing SFTP users.
*/}}
{{- define "wordpress.sftpSecretName" -}}
{{- $name := include "wordpress.name" . -}}
{{- printf "%s-sftp" $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
