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

{{/*
Pod-level securityContext body, shared by Deployment, CronJob and scheduler.
Usage: {{- include "wac.podSecurityContext" . | nindent N }}
*/}}
{{- define "wac.podSecurityContext" -}}
{{- if .Values.preventRoot -}}
fsGroup: {{ .Values.deployment.gid }}
runAsUser: {{ .Values.deployment.uid }}
runAsNonRoot: true
{{- else -}}
runAsUser: 0
runAsNonRoot: false
{{- end -}}
{{- end -}}

{{/*
Container-level securityContext body, shared by Deployment, CronJob and scheduler.
*/}}
{{- define "wac.containerSecurityContext" -}}
{{- if .Values.preventRoot -}}
runAsUser: {{ .Values.deployment.uid }}
runAsGroup: {{ .Values.deployment.gid }}
runAsNonRoot: true
allowPrivilegeEscalation: false
{{- else -}}
runAsUser: 0
runAsNonRoot: false
{{- end -}}
{{- end -}}

{{/*
serviceAccountName + imagePullSecrets pod spec fields (may render empty).
*/}}
{{- define "wac.podIdentity" -}}
{{- if .Values.deployment.serviceAccountName }}
serviceAccountName: {{ .Values.deployment.serviceAccountName }}
{{- end }}
{{- if .Values.imagePullSecrets }}
imagePullSecrets:
  {{- range .Values.imagePullSecrets }}
  - name: {{ . }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
envFrom list items: existingConfigMapsEnv, existingSecretsEnv, onePasswordSecrets.
*/}}
{{- define "wac.envFrom" -}}
{{- range .Values.deployment.existingConfigMapsEnv }}
- configMapRef:
    name: {{ . }}
{{- end }}
{{- range .Values.deployment.existingSecretsEnv }}
- secretRef:
    name: {{ . }}
{{- end }}
{{- range .Values.onePasswordSecrets }}
- secretRef:
    name: {{ .name }}
{{- end }}
{{- end -}}

{{/*
volumeMounts list items for a subset of the main `volumes`, plus the
1Password secrets that declare mountPaths. Unknown names are ignored.
Usage: include "wac.selectedVolumeMounts" (dict "root" $ "names" $names)
*/}}
{{- define "wac.selectedVolumeMounts" -}}
{{- $root := .root -}}
{{- range $volName := .names }}
{{- range $volume := $root.Values.volumes }}
{{- if eq $volume.name $volName }}
{{- range $mountPath := $volume.mountPaths }}
- name: {{ include "wac.name" $root }}-{{ $volume.name }}
  mountPath: {{ $mountPath.path }}
  subPath: {{ $mountPath.subPath | default "" }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- range $secret := $root.Values.onePasswordSecrets }}
{{- range $mountPath := $secret.mountPaths }}
- name: op-{{ $secret.name }}
  mountPath: {{ $mountPath.path }}
  subPath: {{ $mountPath.subPath | default "" }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
volumes list items matching "wac.selectedVolumeMounts".
Usage: include "wac.selectedVolumes" (dict "root" $ "names" $names)
*/}}
{{- define "wac.selectedVolumes" -}}
{{- $root := .root -}}
{{- range $volName := .names }}
{{- range $volume := $root.Values.volumes }}
{{- if eq $volume.name $volName }}
- name: {{ include "wac.name" $root }}-{{ $volume.name }}
  {{- if $volume.configMap }}
  configMap:
    name: {{ $volume.configMap }}
  {{- else if $volume.secret }}
  secret:
    secretName: {{ $volume.secret }}
  {{- else }}
  persistentVolumeClaim:
    claimName: {{ include "wac.name" $root }}-{{ $volume.name }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- range $root.Values.onePasswordSecrets }}
{{- if .mountPaths }}
- name: op-{{ .name }}
  secret:
    secretName: {{ .name }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Scheduling for CronJob and scheduler pods: tolerations from
deployment.nodeAffinity, nodeSelector from the top-level nodeSelector.
Unlike the web Deployment there is no required nodeAffinity: these pods
tolerate the tainted nodes but may also run elsewhere.
*/}}
{{- define "wac.jobScheduling" -}}
{{- with .Values.deployment.nodeAffinity }}
tolerations:
  {{- range $key, $value := . }}
  - key: {{ $key | quote }}
    operator: "Equal"
    value: {{ $value | quote }}
    effect: "NoSchedule"
  {{- end }}
{{- end }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Validates .Values.cronjobs; renders nothing, fails on invalid input.
Included by both cronjob.yaml and scheduler.yaml.
*/}}
{{- define "wac.validateCronjobs" -}}
{{- $seen := dict -}}
{{- $schedulerOnlyUnsupported := list "restartPolicy" "concurrencyPolicy" "activeDeadlineSeconds" "backoffLimit" "suspend" "startingDeadlineSeconds" "ttlSecondsAfterFinished" "successfulJobsHistoryLimit" "failedJobsHistoryLimit" "image" "resources" "timeZone" -}}
{{- range $i, $job := .Values.cronjobs -}}
{{- if not $job.name -}}
{{- fail (printf "cronjobs[%d]: `name` is required" $i) -}}
{{- end -}}
{{- if hasKey $seen $job.name -}}
{{- fail (printf "cronjobs: duplicate job name %q (names must be unique within the release)" $job.name) -}}
{{- end -}}
{{- $_ := set $seen $job.name true -}}
{{- $runIn := $job.runIn | default "job" -}}
{{- if not (has $runIn (list "job" "scheduler")) -}}
{{- fail (printf "cronjobs[%s]: runIn must be \"job\" or \"scheduler\", got %q" $job.name (toString $runIn)) -}}
{{- end -}}
{{- if eq $runIn "scheduler" -}}
{{- range $key := $schedulerOnlyUnsupported -}}
{{- if and (hasKey $job $key) (not (kindIs "invalid" (get $job $key))) -}}
{{- if eq $key "suspend" -}}
{{- fail (printf "cronjobs[%s]: `suspend` has no effect with runIn: scheduler. To pause a scheduler job, remove it from the list (or move it back to runIn: job)" $job.name) -}}
{{- else if eq $key "timeZone" -}}
{{- fail (printf "cronjobs[%s]: per-job `timeZone` is not supported with runIn: scheduler; set `scheduler.timeZone` (applies to all scheduler jobs) or adjust the schedule" $job.name) -}}
{{- else if eq $key "image" -}}
{{- fail (printf "cronjobs[%s]: `image` cannot be overridden with runIn: scheduler (the scheduler runs the release image); use runIn: job" $job.name) -}}
{{- else if eq $key "resources" -}}
{{- fail (printf "cronjobs[%s]: per-job `resources` have no effect with runIn: scheduler (all jobs share the scheduler pod); size it with `scheduler.resources`" $job.name) -}}
{{- else -}}
{{- fail (printf "cronjobs[%s]: `%s` has no effect with runIn: scheduler (supercronic runs the command in the scheduler pod: no Job, no retries, no deadline, never two runs of the same job at once). Remove it, or keep the job on runIn: job" $job.name $key) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if not $job.command -}}
{{- fail (printf "cronjobs[%s]: `command` is required with runIn: scheduler (the image entrypoint is not used)" $job.name) -}}
{{- end -}}
{{- if contains "\n" (toString $job.schedule) -}}
{{- fail (printf "cronjobs[%s]: schedule must be a single line" $job.name) -}}
{{- end -}}
{{- range $arg := concat $job.command ($job.args | default list) -}}
{{- if contains "\n" (toString $arg) -}}
{{- fail (printf "cronjobs[%s]: command/args cannot contain newlines with runIn: scheduler (one crontab line per job)" $job.name) -}}
{{- end -}}
{{- end -}}
{{- range $key, $value := $job.env -}}
{{- if not (regexMatch "^[A-Za-z_][A-Za-z0-9_]*$" $key) -}}
{{- fail (printf "cronjobs[%s]: env name %q is not a valid shell variable name" $job.name $key) -}}
{{- end -}}
{{- if contains "\n" (toString $value) -}}
{{- fail (printf "cronjobs[%s]: env %s cannot contain newlines with runIn: scheduler" $job.name $key) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Single-quotes a value for /bin/sh: wraps it in '...' and escapes embedded
single quotes as '\''. (sprig's `squote` alone does not escape them.)
*/}}
{{- define "wac.shellQuote" -}}
{{- printf "'%s'" (replace "'" "'\\''" (toString .)) -}}
{{- end -}}

{{/*
Crontab content for supercronic: one line per runIn: scheduler job.
Format: <schedule> [VAR='value' ...] 'command' 'arg' ...
supercronic passes the command verbatim to `/bin/sh -c`: `%` has no special
meaning (unlike Vixie cron) and must NOT be escaped.
*/}}
{{- define "wac.crontab" -}}
# Generated by the wac chart for release {{ .Release.Name }}. Do not edit.
{{- with .Values.scheduler.timeZone }}
CRON_TZ={{ . }}
{{- end }}
{{- range $job := .Values.cronjobs }}
{{- if eq ($job.runIn | default "job") "scheduler" }}
{{- $parts := list }}
{{- range $key, $value := $job.env }}
{{- $parts = append $parts (printf "%s=%s" $key (include "wac.shellQuote" $value)) }}
{{- end }}
{{- range $arg := concat $job.command ($job.args | default list) }}
{{- $parts = append $parts (include "wac.shellQuote" $arg) }}
{{- end }}
# {{ $job.name }}
{{ $job.schedule }} {{ join " " $parts }}
{{- end }}
{{- end }}
{{ end -}}
