{{- define "wac.name" -}}
{{- default .Chart.Name .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Define helper for managing SFTP users.
*/}}
{{- define "wac.sftpSecretName" -}}
{{- $name := include "wac.name" . -}}
{{- printf "%s-sftp" $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
