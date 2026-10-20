# Changelog

## [2.0.0] - 2026-10-20

### Breaking Changes

#### Nuovi default per i CronJob esistenti (`runIn: job`)
Ogni CronJob riceve i valori di `cronjobDefaults`, salvo valore esplicito sul job (precedenza: job > `cronjobDefaults` > campo non emesso):

| Campo | Prima (1.10.0) | Ora |
|---|---|---|
| `resources` | `deployment.resources` (spesso `{}` → pod BestEffort) | `requests: {cpu: 50m, memory: 64Mi}`, `limits: {memory: 256Mi}`. **Non ripiega più su `deployment.resources`** |
| `ttlSecondsAfterFinished` | non emesso (Job tenuti secondo gli history limit) | `3600` |
| `activeDeadlineSeconds` | non emesso (nessun limite) | `3600` |
| `backoffLimit` | non emesso (default Kubernetes: 6) | `1` |
| `timeZone` | non emesso (UTC) | `""`: invariato, UTC |

Conseguenze da verificare prima dell'upgrade:
- **Un job che dura più di un'ora viene interrotto** (`DeadlineExceeded`). Impostare `activeDeadlineSeconds` sul job (es. `1500` per un job da 15 minuti) o `null` per nessun limite.
- **Memoria**: un job che contava su `deployment.resources` o che usa più di 256Mi viene ucciso per OOM. Impostare `resources` sul job.
- **Retry**: un job che fallisce viene ritentato una volta, non più sei.
- **TTL**: i Job finiti, falliti compresi, vengono cancellati con i loro pod dopo un'ora. Log e stato di un fallimento notturno non sono più visibili al mattino con `kubectl`: vanno guardati su CloudWatch/Graylog.

#### Label dei pod dei CronJob
I pod dei CronJob passano da `app.kubernetes.io/name: <release>` a `<release>-cronjob` (dettaglio sotto, in Fixed). Selettori `kubectl -l` e filtri di log/monitoring che usavano la label vecchia non li trovano più.

#### Migration Guide
Per conservare il comportamento della 1.10.0 su un singolo job:
```yaml
cronjobs:
  - name: report
    # ...
    resources: { requests: { cpu: 500m, memory: 1Gi } }   # oppure: resources: {} per nessuna risorsa
    activeDeadlineSeconds: null
    backoffLimit: null
    ttlSecondsAfterFinished: null
```
Per tutta la release: gli stessi campi a `null` sotto `cronjobDefaults`.

Nei progetti og-ci: aggiornare `chartVersion` in `.config/config.yml` (es. `~2.0.0`); un pin `~1.x.0` continua a usare l'ultima 1.x.

### Added
- `cronjobs[].runIn`: `job` (default, CronJob Kubernetes) o `scheduler`
- **Scheduler per release** (`templates/scheduler.yaml`), creato solo se almeno un job ha `runIn: scheduler`:
  - ConfigMap `<release>-crontab` (una riga per job) e Deployment `<release>-scheduler` con [supercronic](https://github.com/aptible/supercronic) v0.2.49, stessa immagine della release
  - `replicas: 1`, `strategy: Recreate`; selettore con `app.kubernetes.io/name: <release>-scheduler`, quindi non combacia con il Deployment web né con il Service
  - Eredita env, envFrom, 1Password secret, securityContext, serviceAccount, imagePullSecrets, tolerations e nodeSelector come i CronJob
  - Volumi: unione dei `volumes` dei job scheduler
  - Annotazione `checksum/crontab`: il pod si riavvia quando cambia un job
  - Metriche Prometheus su `:9746/metrics` (`scheduler.metrics`), con annotazioni `prometheus.io/*`
  - `scheduler.timeZone` (scritto come `CRON_TZ`), `scheduler.extraArgs`, `scheduler.resources`, `scheduler.terminationGracePeriodSeconds`
  - Prerequisito: `supercronic` nel PATH dell'immagine
- `cronjobs[].ttlSecondsAfterFinished` e il blocco `cronjobDefaults`
- Validazioni (`fail`): `runIn` non valido, nomi dei job duplicati, campi senza effetto con `runIn: scheduler` (`restartPolicy`, `concurrencyPolicy`, `activeDeadlineSeconds`, `backoffLimit`, `suspend`, `startingDeadlineSeconds`, `ttlSecondsAfterFinished`, history limit, `image`, `resources`, `timeZone`), `command` mancante, newline in command/args/env

### Fixed
- **CronJob: i pod non vengono più selezionati dal Service e dal Deployment web.** Avevano le stesse label `app.kubernetes.io/name` + `instance` del web, quindi mentre giravano finivano tra gli endpoint del Service (e tra i target dell'ALB) senza nessun server in ascolto, e pesavano nella `podAntiAffinity` del web. Ora i pod dei CronJob hanno `app.kubernetes.io/name: <release>-cronjob` e `app.kubernetes.io/part-of: <release>`; le label dell'oggetto CronJob non cambiano
  - Da aggiornare se presenti: filtri di log/monitoring o comandi `kubectl -l app.kubernetes.io/name=<release>` usati per trovare i pod dei job. Usare `app.kubernetes.io/name=<release>-cronjob`, `app.kubernetes.io/component=cronjob-<job>` o `app.kubernetes.io/part-of=<release>`
  - I Job già in esecuzione al momento dell'upgrade mantengono le label vecchie fino alla fine
- CronJob: `nodeSelector` veniva emesso solo se `deployment.nodeAffinity` non era vuoto. Ora è emesso quando `nodeSelector` è valorizzato, come nel Deployment

### Changed
- Security context, serviceAccount/imagePullSecrets, envFrom, volumi e tolerations estratti in helper di `_helpers.tpl`, condivisi da Deployment, CronJob e scheduler. Il manifest del Deployment web è invariato

## [1.10.0] - 2026-08-31

### Added
- CronJob: campo opzionale `timeZone` per ogni entry di `cronjobs[]`
  - Finisce in `spec.timeZone` del CronJob (`batch/v1`), GA da Kubernetes 1.27: su cluster più vecchi il campo viene ignorato o rifiutato
  - Senza il campo la schedule è valutata nel fuso locale del kube-controller-manager (UTC su EKS), quindi i confini di giorno/mese si spostano di un'ora due volte l'anno rispetto all'ora locale
  - Opzionale, emesso solo se valorizzato: senza il campo il manifest resta identico a prima
  - Evitare schedule nella finestra `02:00-03:00` locale nei fusi europei: a marzo quell'ora non esiste (esecuzione saltata), a ottobre è doppia (possibile esecuzione ripetuta)

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
