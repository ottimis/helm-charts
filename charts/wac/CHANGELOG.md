# Changelog

## [1.9.0] - 2026-07-23

### Added
- CronJob: campi opzionali `startingDeadlineSeconds`, `activeDeadlineSeconds` e `backoffLimit` per ogni entry di `cronjobs[]`
  - `startingDeadlineSeconds` sulla spec del CronJob; `activeDeadlineSeconds` e `backoffLimit` sullo spec del Job
  - Senza timeout un job appeso, con `concurrencyPolicy: Forbid`, blocca per sempre le esecuzioni successive
  - Tutti opzionali, default = comportamento invariato (nessun campo emesso se non valorizzato)
  - `backoffLimit` valutato con `hasKey` (non truthiness) così `0` è un valore valido

## [1.8.0] - 2026-07-10

### Added
- Supporto `extraVolumes[]` / `extraVolumeMounts[]`: passthrough di volumi e mount arbitrari nel deployment (es. token proiettati per Workload Identity Federation)

## [1.7.0] - 2026-04-14

### Added
- Supporto `mountPaths` per `onePasswordSecrets[]`: possibilità di montare un 1Password Secret come volume (file) oltre che come env vars
  - Stessa sintassi dei volumi principali: `path` e `subPath`
  - Supportato sia nel deployment che nei cronjob

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
