# Changelog

## [1.6.0] - 2026-04-06

### Added
- Supporto 1Password Secrets tramite `onePasswordSecrets[]`
  - Crea risorse `OnePasswordItem` che il 1Password Operator sincronizza come Secret Kubernetes
  - Iniettati automaticamente come env vars nel deployment e nei cronjob
  - Configurabile: `vault` (default: `eks`), `autoRestart` (default: `true`)

## [1.5.0] - 2026-04-06

### Changed
- `preventRoot: false` ora forza esplicitamente `runAsUser: 0` a livello pod e container (prima non applicava securityContext)

## [1.4.0] - 2026-03-25

### Added
- Supporto CronJob: possibilità di definire job schedulati tramite `cronjobs[]`
  - Usa la stessa immagine del deployment (o override custom)
  - Eredita env vars, secrets e configmaps dal deployment
  - Monta volumi selettivamente dal pool principale tramite `volumes[]`
  - Supporta `concurrencyPolicy`, `suspend`, `restartPolicy`, history limits
  - Rispetta `preventRoot`, `imagePullSecrets`, `serviceAccountName`, `nodeAffinity`

## [1.3.1] - 2026-03-25

### Added
- Supporto `imagePullSecrets` per pull da registry privati
- Supporto `service.ports[]` per servizi multi-porta (HTTP + WebSocket, gRPC, etc.)
- `additionalRoutesBefore/After` ora supportano `serviceName` opzionale (default: servizio corrente) e `pathType`
- `subPath` nello schema dei volumi per montare file singoli da ConfigMap/Secret

### Changed
- `preventRoot: false` ora forza esplicitamente `runAsUser: 0` (prima non applicava securityContext)

## [1.0.0] - 2025-09-26
### Changed
- ⚠️ Prima il `subPath` di tutti i volumi corrispondeva automaticamente al `name` del volume.  
  Ora il `subPath` deve essere inserito **esplicitamente**.  
  Verifica i tuoi valori di configurazione prima dell’upgrade.
