# wac — Web Application Component

Chart Helm generico di Ottimis per applicazioni web (PHP, Node.js, NestJS, ...). Riferimento completo dei valori: [`values.yaml`](values.yaml) e [`values.schema.json`](values.schema.json); storico: [`CHANGELOG.md`](CHANGELOG.md).

## Job schedulati: `cronjobs[]`

Ogni entry di `cronjobs[]` gira in uno di due modi, scelti con `runIn`.

| | `runIn: job` (default) | `runIn: scheduler` |
|---|---|---|
| Risorsa | Un `CronJob` per job, **un pod per esecuzione** | Un solo `Deployment` `<release>-scheduler` per release, con [supercronic](https://github.com/aptible/supercronic) |
| Quando | Job lunghi o pesanti, job che serve isolare (risorse, retry, deadline proprie) | Job frequenti e brevi, ogni 1-15 minuti |
| Fuso della schedule | `timeZone` del job o `cronjobDefaults.timeZone`; vuoto = **UTC** | `scheduler.timeZone`; vuoto = **TZ del container** (Europe/Rome nell'immagine PHP base) |
| Sovrapposizioni | `concurrencyPolicy` (default `Forbid`) | Mai: un job non parte finché la sua esecuzione precedente non è finita |
| Timeout / retry | `activeDeadlineSeconds`, `backoffLimit` | Nessuno: lo script deve gestirli da sé |
| Costo | sandbox, IP VPC, scritture su etcd a ogni esecuzione | Un pod sempre acceso (20m CPU / 64Mi richiesti) |

Una regola pratica: se lo script dura meno dell'avvio del pod e gira più spesso di ogni 15 minuti, va nello scheduler.

### `runIn: job`

```yaml
cronjobDefaults:            # applicati a tutti i job runIn: job
  resources:
    requests: { cpu: 50m, memory: 64Mi }
    limits:   { memory: 256Mi }
  ttlSecondsAfterFinished: 3600
  activeDeadlineSeconds: 3600
  backoffLimit: 1
  timeZone: ""              # vuoto = UTC

cronjobs:
  - name: fitp
    schedule: "*/30 * * * *"
    command: ["php", "/var/www/html/scripts/fitp.php"]
    activeDeadlineSeconds: 1500   # dura 13-14 minuti
    resources:
      requests: { cpu: 200m, memory: 512Mi }
```

Precedenza: valore del job > `cronjobDefaults` > campo non emesso. Un job disattiva un default con `null` (`resources: {}` per nessuna risorsa); `backoffLimit: 0` è valido.

### `runIn: scheduler`

```yaml
scheduler:
  resources:
    requests: { cpu: 20m, memory: 64Mi }
    limits:   { memory: 256Mi }
  terminationGracePeriodSeconds: 300
  metrics: { enabled: true, port: 9746 }
  timeZone: ""             # vuoto = TZ del container
  extraArgs: []

cronjobs:
  - name: send-campaigns
    schedule: "* * * * *"
    command: ["php", "/var/www/html/scripts/send-campaign.php"]
    runIn: scheduler
  - name: reservations-tick
    schedule: "*/5 * * * *"
    command: ["php", "/var/www/html/scripts/tick.php"]
    args: ["--limit", "100"]
    env: { TICK_MODE: "fast" }   # solo per questo job
    runIn: scheduler
```

Campi ammessi: `name`, `schedule`, `command` (obbligatorio: l'entrypoint dell'immagine non viene usato), `args`, `env`, `volumes`. Gli altri campi dei CronJob (`restartPolicy`, `concurrencyPolicy`, `activeDeadlineSeconds`, `backoffLimit`, `suspend`, `timeZone`, `image`, `resources`, ...) fanno fallire il rendering, perché con lo scheduler non avrebbero effetto. Per sospendere un job dello scheduler basta toglierlo dalla lista.

Cosa genera il chart:
- ConfigMap `<release>-crontab`, una riga per job: `<schedule> [VAR='v' ...] 'command' 'arg' ...`. Ogni argomento è tra apici singoli: nessuna espansione di shell (`$(...)`, `$VAR`, `*`); per usarla, `command: ["sh", "-c", "..."]`.
- Deployment `<release>-scheduler`: `replicas: 1`, `strategy: Recreate`, stessa immagine, env/envFrom/1Password/securityContext/serviceAccount/tolerations/nodeSelector dei CronJob, volumi uniti dei job scheduler. Comando: `supercronic -passthrough-logs [-prometheus-listen-address :<port>] <extraArgs> /etc/supercronic/crontab`.
- Annotazione `checksum/crontab`: il pod si riavvia quando cambia un job.
- Selettore con `app.kubernetes.io/name: <release>-scheduler` e `app.kubernetes.io/component: scheduler`: il pod non riceve traffico dal Service e non viene contato dal Deployment web.
- Nessuna probe HTTP. Con `metrics.enabled` espone `:9746/metrics` (serie `supercronic_*`: esecuzioni, successi, fallimenti, durata, job in ritardo) con annotazioni `prometheus.io/scrape|port|path`.

#### Comportamento di supercronic (v0.2.49, verificato su README e sorgenti)

- **Sovrapposizioni**: di default non lancia un job mentre la sua esecuzione precedente è in corso; logga `not starting: job is still running` e salta il turno. Si cambia con `extraArgs: ["-overlapping"]`, da non usare salvo job idempotenti.
- **SIGTERM** (deploy, drain): smette di schedulare e **aspetta la fine dei job in corso**, poi esce. Kubernetes li uccide con SIGKILL allo scadere di `terminationGracePeriodSeconds` (default 300): tenerlo ≥ della durata del job più lungo nello scheduler.
- **Fuso orario**: usa `/etc/localtime` o la variabile `TZ` del container; `CRON_TZ` nel crontab (`scheduler.timeZone`) lo sovrascrive solo per le schedule. Il fuso deve esistere in `tzdata` dell'immagine.
- **`%`**: nessun significato speciale (a differenza di Vixie cron, dove diventa newline). Il comando passa a `/bin/sh -c` così com'è: il chart non fa escape di `%`.
- **Log**: con `-passthrough-logs` l'output dei job va su stdout/stderr del pod senza wrapper; supercronic logga in più l'avvio e l'esito di ogni esecuzione.
- **Schedule**: accetta 5 campi (standard), 6 (+ anno) o 7 (secondi + ... + anno) e le scorciatoie `@hourly` ecc.

#### Prerequisito: `supercronic` nell'immagine

Il binario deve stare nel `PATH` dell'immagine della release.
- **Immagine PHP base** (`public.ecr.aws/ottimis/php`): incluso da `8.5.11-alpine` in tutte le varianti (pacchetto Alpine, repo `Libs/Docker/php`). Con un tag precedente il pod scheduler va in `CrashLoopBackOff` con `executable file not found`: aggiornare prima l'immagine del progetto.
- **Immagini Node, Python o altre**: aggiungerlo nel Dockerfile del progetto, ad esempio:

```dockerfile
ARG SUPERCRONIC_VERSION=v0.2.49
ARG TARGETARCH
RUN curl -fsSL -o /usr/local/bin/supercronic \
      "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${TARGETARCH}" \
 && echo "<sha256 della release per l'architettura>  /usr/local/bin/supercronic" | sha256sum -c - \
 && chmod +x /usr/local/bin/supercronic
```

#### Cose da sapere

- **Fuso orario e migrazione**: un CronJob senza `timeZone` gira in UTC; supercronic usa il TZ del container (Europe/Rome nell'immagine base). Spostando un job nello scheduler senza correggere lo schedule, **l'orario cambia di 1-2 ore** (1 d'inverno, 2 d'estate). Per i job ogni N minuti non cambia nulla; per quelli a orario fisso, correggere lo schedule o impostare `scheduler.timeZone: "UTC"`. Evitare le 02:00-03:00 locali (ora inesistente a marzo, doppia a ottobre).
- **Una sola replica**: durante un deploy o un drain del nodo (Recreate: il vecchio pod termina prima che parta il nuovo) i job saltano per circa un minuto, di più se un job in corso allunga lo shutdown. I job critici devono essere **idempotenti** o prendere un **lock** (Redis `SET NX EX` o riga DB). Le esecuzioni saltate non vengono recuperate.
- **Risorse condivise**: tutti i job della release condividono CPU e memoria del pod scheduler. Un job che va in OOM uccide il container e interrompe anche gli altri. Dimensionare `scheduler.resources` sul caso peggiore di job concorrenti, o tenere i job pesanti su `runIn: job`.
- **Volumi RWO**: un PVC `ReadWriteOnce` montato dal Deployment web non è montabile dallo scheduler su un altro nodo; usare RWX (EFS) o non montarlo.
- **Worker permanenti**: un job che gira ogni minuto e dura ~60 secondi è un worker, non un job schedulato: va trasformato in un Deployment con ciclo interno, non spostato nello scheduler.

#### Migrazione da CronJob a scheduler

1. Verificare che l'immagine contenga `supercronic` (`docker run --rm <image> supercronic -version`).
2. Rendere lo script idempotente, o protetto da lock, se un'esecuzione saltata o ripetuta crea problemi.
3. Sul job: aggiungere `runIn: scheduler`; togliere `concurrencyPolicy`, `restartPolicy`, `activeDeadlineSeconds`, `backoffLimit`, `suspend`, `timeZone`, `resources`, `image`, history limit (il rendering fallisce finché ci sono). Il timeout, se serve, va dentro lo script, ad esempio `command: ["timeout", "300", "php", "..."]`.
4. Controllare il fuso orario dello schedule (vedi sopra).
5. `helm template` / `helm diff`: il CronJob sparisce, compaiono `<release>-crontab` e `<release>-scheduler`. All'upgrade Helm cancella il CronJob e crea lo scheduler; i Job già in corso del vecchio CronJob vengono cancellati insieme a lui.
6. Dopo il deploy: `kubectl logs deploy/<release>-scheduler`, e la metrica `supercronic_failed_executions` per i fallimenti.

Primi candidati:

| CronJob | Frequenza | Durata | Modalità |
|---|---|---|---|
| lindhaus/send-mail-campaigns | ogni minuto | 3 s | scheduler |
| qrcodenow/og-qr-web-billing-renewals | ogni minuto | 3-5 s | scheduler (richiede idempotenza) |
| mobee/backend-reservations-tick | */5 | 3 s | scheduler |
| mobee/backend-scan-metering | */15 | 3 s | scheduler |
| og-services/og-notify-escalations | */5 | 3 s | scheduler |
| jack/jack-web-hud-live-worker | ogni minuto | 59 s | nessuna delle due: worker permanente, da trasformare in Deployment con ciclo interno |
| tennis-now/tennisnow-fitp | */30 | 13-14 min | job, con `activeDeadlineSeconds: 1500` |
