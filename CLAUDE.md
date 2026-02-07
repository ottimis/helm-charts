# Helm Charts Repository

Repository di Helm charts custom sviluppati da Ottimis per il deployment di applicazioni web su Kubernetes.

## Struttura del Repository

```
charts/
├── wac/           # Web Application Component - chart generico per applicazioni PHP
└── wordpress/     # Chart specifico per WordPress
```

---

## Chart: WAC (Web Application Component)

**Versione:** 1.1.2
**App Version:** 1.0.0
**Maintainer:** MM <mm@ottimis.com>

### Descrizione

Chart Helm generico per il deployment di applicazioni web (PHP, Node.js, NestJS, etc.). Progettato per essere flessibile e riutilizzabile, supporta container custom, **servizi multi-porta** (HTTP + WebSocket), volumi persistenti multipli, accesso SFTP opzionale e integrazione con AWS ALB Ingress Controller.

### Architettura

```
┌─────────────────────────────────────────────────────────────┐
│                         Ingress (ALB)                        │
│                    (se ingress.enabled=true)                 │
└─────────────────────────────────┬───────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────┐
│                          Service                             │
│                   (ClusterIP, porta 80)                      │
└─────────────────────────────────┬───────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────┐
│                        Deployment                            │
│  ┌─────────────────────────┐  ┌─────────────────────────┐   │
│  │    Container PHP        │  │   Container SFTP        │   │
│  │    (porta 8080)         │  │   (porta 22, opzionale) │   │
│  └───────────┬─────────────┘  └───────────┬─────────────┘   │
│              │                            │                  │
│              └────────────┬───────────────┘                  │
│                           ▼                                  │
│              ┌─────────────────────────┐                     │
│              │   Volumi Condivisi      │                     │
│              │   (PVC / ConfigMap /    │                     │
│              │    Secret)              │                     │
│              └─────────────────────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

### Risorse Kubernetes Generate

| Risorsa | File Template | Condizione |
|---------|---------------|------------|
| Deployment | `templates/deployment.yaml` | Sempre |
| Service | `templates/service.yaml` | Sempre |
| Ingress | `templates/ingress.yaml` | `ingress.enabled: true` |
| PersistentVolumeClaim | `templates/pvc.yaml` | Per ogni volume senza configMap/secret |
| ConfigMap (SFTP) | `templates/sftp-configmap.yaml` | `sftp.enabled: true` |
| Service (SFTP) | `templates/sftp-service.yaml` | `sftp.enabled: true` |

### Configurazione Principale

#### Immagine e Scaling

```yaml
replicaCount: 1                    # Numero di repliche
updateStrategy: "RollingUpdate"    # Strategia di update (RollingUpdate/Recreate)
preventRoot: true                  # Esegue container come non-root

image:
  repository: 348705108113.dkr.ecr.eu-central-1.amazonaws.com/ottimis/php:8.3.11-bullseye
  pullPolicy: IfNotPresent
```

#### Service

**Configurazione singola porta (default):**

```yaml
service:
  type: ClusterIP
  port: 80
  targetPort: 8080
```

**Configurazione multi-porta** (per HTTP + WebSocket, gRPC, etc.):

```yaml
service:
  type: ClusterIP
  ports:
    - name: http
      port: 80
      targetPort: 3000
    - name: ws
      port: 3001
      targetPort: 3001
```

> **Nota**: Se `service.ports` è definito, sovrascrive `port`/`targetPort`. La retrocompatibilità è garantita: configurazioni esistenti senza `ports` continuano a funzionare.

#### Ingress (AWS ALB)

```yaml
ingress:
  enabled: false
  className: "alb"
  certificateArn: ""              # ARN certificato ACM per HTTPS
  groupName: "frontend-public"    # Nome gruppo ALB condiviso
  customAnnotations: {}
  hosts: []
  path: "/"
  additionalRoutesBefore: []      # Route aggiuntive con priorità maggiore
  additionalRoutesAfter: []       # Route aggiuntive con priorità minore
```

**Additional Routes**: Le route in `additionalRoutesBefore` e `additionalRoutesAfter` supportano:
- `path` (obbligatorio): Path di routing (es. `/socket.io`)
- `servicePort`: Porta del service a cui instradare (default: 80)
- `serviceName`: Nome del service (default: il service corrente)
- `pathType`: Tipo di path matching (`Prefix`, `Exact`, `ImplementationSpecific`; default: `Prefix`)

#### Deployment Avanzato

```yaml
deployment:
  customHtaccessCM: ""            # Nome ConfigMap con htaccess custom
  existingSecretsEnv: []          # Lista Secret da montare come env
  existingConfigMapsEnv: []       # Lista ConfigMap da montare come env
  env: {}                         # Variabili d'ambiente inline
  customIniCM: ""                 # Nome ConfigMap con php.ini custom
  resources: {}                   # Limiti risorse CPU/memoria
  uid: 1000                       # UID utente container
  gid: 1000                       # GID gruppo container
  gracefulShutdownSeconds: 60     # Tempo graceful shutdown
  serviceAccountName: ""          # ServiceAccount custom
  nodeAffinity: {}                # Node affinity/tolerations
  preventSameNode: true           # Anti-affinity per HA
```

#### Volumi

Sistema flessibile per gestire volumi persistenti, ConfigMap e Secret:

```yaml
volumes:
  - name: "data"
    mountPaths:
      - name: moduli
        path: /var/www/html
        subPath: ""               # SubPath per montare un singolo file da ConfigMap/Secret
    # Usa UNO tra: PVC (default), configMap, o secret
    configMap: ""                 # Nome ConfigMap esistente
    secret: ""                    # Nome Secret esistente
    # Solo per PVC:
    accessMode: "ReadWriteOnce"
    size: "8Gi"
    storageClass: "gp3"
    sftpAccess: false             # Monta volume anche nel container SFTP
```

**Montare un file singolo da Secret/ConfigMap:**

```yaml
volumes:
  - name: "firebase-config"
    mountPaths:
      - name: settings
        path: /app/firebase/config.json
        subPath: config.json      # Chiave nel Secret/ConfigMap
    secret: "firebase-config"     # Nome Secret esistente
```

#### SFTP

Container sidecar per accesso SFTP ai volumi:

```yaml
sftp:
  enabled: false
  users:
    - username: "username"
      password: "$1$..."          # Password hash (openssl passwd -1)
      uid: 1000
      gid: 1000
  image:
    tag: "latest"
```

### Features Principali

1. **Multi-Port Service**: Supporto per servizi con porte multiple (HTTP + WebSocket, gRPC, etc.)
2. **Security Context**: Esecuzione non-root configurabile, security context per pod e container
3. **Node Affinity/Tolerations**: Scheduling avanzato tramite `deployment.nodeAffinity`
4. **Pod Anti-Affinity**: Distribuzione automatica su nodi diversi per HA
5. **Graceful Shutdown**: Configurabile con preStop hook
6. **Volumi Flessibili**: Supporto PVC, ConfigMap e Secret con mount multipli e subPath
7. **SFTP Sidecar**: Accesso file via SFTP con utenti configurabili
8. **ALB Integration**: Annotazioni native per AWS ALB Ingress Controller
9. **Resource Policy**: PVC mantenuti alla cancellazione del chart (`helm.sh/resource-policy: keep`)

---

### Esempio: NestJS con HTTP + WebSocket

Configurazione completa per un backend NestJS che espone HTTP sulla porta 3000 e WebSocket sulla porta 3001, entrambi accessibili dallo stesso dominio:

```yaml
# values.yaml
image:
  repository: my-registry/nestjs-app:latest
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  ports:
    - name: http
      port: 80
      targetPort: 3000      # Porta HTTP NestJS
    - name: ws
      port: 3001
      targetPort: 3001      # Porta WebSocket NestJS

ingress:
  enabled: true
  className: "alb"
  certificateArn: "arn:aws:acm:eu-central-1:123456789:certificate/xxx"
  groupName: "backend-public"
  hosts:
    - api.example.com
  path: "/"
  # WebSocket route con priorità maggiore (valutata prima di "/")
  additionalRoutesBefore:
    - path: /socket.io
      servicePort: 3001     # Punta alla porta WS del service
```

**Risultato routing:**
| Path | Destinazione |
|------|--------------|
| `https://api.example.com/socket.io/*` | Service porta 3001 → Container 3001 (WS) |
| `https://api.example.com/*` | Service porta 80 → Container 3000 (HTTP) |

**Note per WebSocket su AWS ALB:**

Se usi Socket.IO con più repliche, abilita sticky sessions:

```yaml
ingress:
  customAnnotations:
    alb.ingress.kubernetes.io/target-group-attributes: stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=86400
```

---

## Chart: WordPress

**Versione:** 1.0.0
**App Version:** 6.9.0
**Maintainer:** MM <mm@ottimis.com>

### Descrizione

Chart Helm specifico per il deployment di WordPress su Kubernetes. Include gestione automatica delle credenziali, integrazione database esterno, supporto cache Memcached, security hardening (blocco XML-RPC), accesso SFTP e configurazione avanzata tramite ConfigMap/Secret esterni.

### Architettura

```
┌─────────────────────────────────────────────────────────────┐
│                     Ingress (ALB)                            │
│              (blocco XML-RPC automatico)                     │
└─────────────────────────────────┬───────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────┐
│                         Service                              │
│                   (ClusterIP, porta 80)                      │
└─────────────────────────────────┬───────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────┐
│                       Deployment                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐   │
│  │   Container WordPress   │  │   Container SFTP        │   │
│  │   (PHP + Apache)        │  │   (opzionale, root)     │   │
│  └───────────┬─────────────┘  └───────────┬─────────────┘   │
│              │                            │                  │
│              └────────────┬───────────────┘                  │
│                           ▼                                  │
│              ┌─────────────────────────┐                     │
│              │     PVC WordPress       │                     │
│              │   (wp-content o full)   │                     │
│              └─────────────────────────┘                     │
└─────────────────────────────────────────────────────────────┘
         │                                      │
         ▼                                      ▼
┌─────────────────┐                  ┌─────────────────────┐
│  Database MySQL │                  │  Memcached (opt.)   │
│    (esterno)    │                  │  (W3 Total Cache)   │
└─────────────────┘                  └─────────────────────┘
```

### Risorse Kubernetes Generate

| Risorsa | File Template | Condizione |
|---------|---------------|------------|
| Deployment | `templates/deployment.yaml` | Sempre |
| Service | `templates/service.yaml` | Sempre |
| Ingress | `templates/ingress.yaml` | `ingress.enabled: true` |
| PersistentVolumeClaim | `templates/pvc.yaml` | `persistence.enabled: true` |
| Secret (Admin Password) | `templates/00-secret.yaml` | Sempre |
| Secret (Salt Keys) | `templates/00-salt.yaml` | Sempre |
| Secret (SFTP) | `templates/sftp-secret.yaml` | `sftp.enabled: true` e `sftp.existingSecret` vuoto |
| Service (SFTP) | `templates/sftp-service.yaml` | `sftp.enabled: true` |
| ConfigMap (W3TC) | `templates/postinit-configmap.yaml` | Cache configurata |

### Configurazione Principale

#### Immagine e Scaling

```yaml
replicaCount: 1
updateStrategy: ""                # Auto: Recreate se RWO, RollingUpdate se RWX
preventRoot: true

image:
  repository: ottimis/wordpress
  pullPolicy: IfNotPresent
  tag: "6.9.0"

resources:
  limits:
    cpu: 200m
    memory: 400Mi
  requests:
    cpu: 50m
    memory: 256Mi
```

#### Database (Obbligatorio)

```yaml
database:
  host: ""                        # Host database MySQL
  name: ""                        # Nome database
  port: ""                        # Porta (default: 3306)
  user: ""                        # Utente database
  existingSecret: ""              # Nome Secret con chiave 'password'
```

#### Deployment

```yaml
deployment:
  uid: 1000                       # UID utente container
  gid: 1000                       # GID gruppo container
  port: 8080                      # Porta container
  existingConfigMapsEnv: []       # Lista ConfigMap da montare come env
  existingSecretsEnv: []          # Lista Secret da montare come env
  nodeAffinity: {}                # Node affinity/tolerations
  preventSameNode: false          # Anti-affinity per HA
```

#### Persistenza

```yaml
persistence:
  enabled: true
  accessMode: ReadWriteOnce       # RWO: monta /var/www/html
                                  # RWX: monta solo /var/www/html/wp-content
  size: 8Gi
  fsGroupChangePolicy: "OnRootMismatch"
```

**Nota importante sulla strategia di update:**
- `ReadWriteOnce`: Forza `Recreate` (volume non condivisibile)
- `ReadWriteMany`: Permette `RollingUpdate` (zero-downtime)

#### WordPress

```yaml
wordpress:
  memoryLimit: 768M               # WP_MEMORY_LIMIT
  configExtraCM: ""               # ConfigMap per WORDPRESS_CONFIG_EXTRA custom
  configExtraKey: ""              # Chiave nel ConfigMap (default: config-extra.php)
  customIniCM: ""                 # ConfigMap con php.ini custom
  cacheHost: ""                   # Host Memcached
  cachePort: ""                   # Porta Memcached
  hostname: ""                    # URL sito (auto-detect da ingress)
  title: "My Blog"                # Titolo sito
  adminUser: "admin"              # Username admin
  adminEmail: "wp@ottimis.com"    # Email admin
  locale: 'it_IT'                 # Locale WordPress
  security:
    enableXmlrpc: false           # Blocca XML-RPC (protezione brute-force)
  customHtaccessCM: ""            # ConfigMap con htaccess custom
  saltKeys:                       # Chiavi di sicurezza (auto-generate se vuote)
    authKey: ""
    secureAuthKey: ""
    loggedInKey: ""
    nonceKey: ""
    authSalt: ""
    secureAuthSalt: ""
    loggedInSalt: ""
    nonceSalt: ""
```

**WORDPRESS_CONFIG_EXTRA**: Per default genera `define('WP_MEMORY_LIMIT', ...)` dal valore `memoryLimit`. Se `configExtraCM` è specificato, il contenuto viene preso dal ConfigMap e `memoryLimit` è ignorato:

```yaml
wordpress:
  configExtraCM: "my-wp-config"
  configExtraKey: "extra.php"     # opzionale, default: config-extra.php
```

#### Ingress (AWS ALB)

```yaml
ingress:
  enabled: false
  className: "alb"
  certificateArn: ""              # ARN certificato ACM per HTTPS
  groupName: "frontend-public"    # Nome gruppo ALB condiviso
  customAnnotations: {}
  hosts: []
```

#### SFTP

Container sidecar per accesso SFTP al PVC WordPress. Le credenziali sono gestite tramite un Secret Kubernetes (non ConfigMap).

```yaml
sftp:
  enabled: false
  existingSecret: ""              # Secret esterno con chiave 'users.conf' (override)
  users:                          # Usato solo se existingSecret è vuoto
    - username: "wordpress"
      password: "$1$..."          # Password hash (openssl passwd -1)
      uid: 1000
      gid: 1000
  image:
    tag: "latest"
```

Se `existingSecret` è specificato, il chart non genera il Secret e usa quello indicato. Il Secret deve contenere la chiave `users.conf` con formato `username:password:e:uid:gid:dir`.

### Security Context e preventRoot

L'immagine WordPress custom (`ottimis/wordpress`) ha `USER www-data` (UID 1000) nel Dockerfile. L'entrypoint originale di WordPress contiene `exec gosu www-data` che sostituisce il processo se eseguito come root, impedendo l'avvio corretto di Apache.

| `preventRoot` | `sftp.enabled` | Pod securityContext | WP container | SFTP container |
|---|---|---|---|---|
| `true` | `false` | `runAsUser: 1000, runAsNonRoot: true, fsGroup: 1000` | `runAsUser: 1000, runAsNonRoot: true` | - |
| `true` | `true` | `runAsUser: 1000, runAsNonRoot: true, fsGroup: 1000` | `runAsUser: 1000, runAsNonRoot: true` | `runAsUser: 0` |
| `false` | `false` | Nessuno (usa USER immagine: www-data/1000) | Nessuno | - |
| `false` | `true` | `fsGroup: 1000` (solo per permessi volume) | Nessuno | `runAsUser: 0` |

> **Importante**: Non forzare `runAsUser: 0` su WordPress. L'entrypoint fa `exec gosu www-data` se rileva root, sostituendo il processo e impedendo l'avvio di Apache.

### Features Principali

1. **Auto-generated Secrets**: Password admin e salt keys generate automaticamente se non specificate
2. **Resource Policy Keep**: Secrets e PVC mantenuti alla cancellazione del chart
3. **XML-RPC Blocking**: Protezione automatica contro attacchi brute-force via XML-RPC
4. **Access Mode Aware**: Mount path e update strategy adattati automaticamente a RWO/RWX
5. **W3 Total Cache Integration**: Script post-init per configurazione automatica Memcached
6. **SFTP Sidecar**: Accesso file via SFTP con container root dedicato (atmoz/sftp)
7. **URL Auto-detection**: URL WordPress derivato automaticamente dal primo host ingress
8. **Security Context**: Gestione intelligente dei permessi tra container WordPress e SFTP
9. **ConfigMap/Secret come Env**: Supporto `existingConfigMapsEnv` e `existingSecretsEnv` per variabili d'ambiente
10. **Custom Config Extra**: `WORDPRESS_CONFIG_EXTRA` configurabile via ConfigMap esterno

### Secret Management

Il chart genera automaticamente tre Secret:

1. **`{release}-admin-password`**: Password admin WordPress (generata random se non esiste)
2. **`{release}-salt-keys`**: 8 chiavi di sicurezza WordPress (generate random se non specificate)
3. **`{release}-sftp`**: Credenziali SFTP `users.conf` (solo se `sftp.enabled: true` e `sftp.existingSecret` vuoto)

I primi due hanno `helm.sh/resource-policy: keep` per persistere tra gli upgrade.

---

## Differenze Principali tra i Chart

| Feature | WAC | WordPress |
|---------|-----|-----------|
| Scopo | Generico (PHP, Node.js, etc.) | WordPress specifico |
| Multi-Port | Supportato (HTTP + WS, gRPC) | Singola porta |
| Volumi | Multipli, configurabili | Singolo PVC per wp-content |
| Database | Via Secret/ConfigMap esterni | Configurazione nativa |
| Secrets | Nessuno generato | Admin password + salt keys |
| Cache | Non inclusa | W3 Total Cache + Memcached |
| Security | Security context | + blocco XML-RPC |
| Update Strategy | Configurabile | Auto-detect da accessMode |
| Env da ConfigMap/Secret | `deployment.existingConfigMapsEnv/existingSecretsEnv` | `deployment.existingConfigMapsEnv/existingSecretsEnv` |

---

## Uso Tipico

### WAC

```bash
helm install myapp ./charts/wac \
  --set image.repository=my-php-app:latest \
  --set ingress.enabled=true \
  --set ingress.hosts[0]=myapp.example.com
```

### WordPress

```bash
helm install myblog ./charts/wordpress \
  --set database.host=mysql.example.com \
  --set database.name=wordpress \
  --set database.user=wpuser \
  --set database.existingSecret=mysql-credentials \
  --set ingress.enabled=true \
  --set ingress.hosts[0]=blog.example.com \
  --set ingress.certificateArn=arn:aws:acm:...
```

---

## Note di Sviluppo

- Entrambi i chart usano AWS ALB Ingress Controller come default
- I PVC hanno `helm.sh/resource-policy: keep` per prevenire perdita dati
- Il container SFTP usa l'immagine `atmoz/sftp` e gira sempre come root (necessario per gestione utenti SSH)
- Le password SFTP devono essere hash MD5 (`openssl passwd -1`)
- Le credenziali SFTP su WordPress sono gestite tramite Secret (non ConfigMap)
- Il template `_helpers.tpl` definisce il naming delle risorse
- L'immagine WordPress custom (`ottimis/wordpress`) usa `USER www-data` (UID 1000) e porta 8080
- Non forzare `runAsUser: 0` su WordPress: l'entrypoint originale fa `exec gosu` e il container muore

---

## Convenzioni per le Modifiche

Quando si apportano modifiche ai chart, seguire **sempre** queste regole:

1. **Aggiornare questo file (`CLAUDE.md`)**: Ogni modifica a values, template o funzionalità deve essere riflessa nella documentazione corrispondente in questo file.

2. **Aggiornare il `CHANGELOG.md` del chart modificato** (`charts/wac/CHANGELOG.md` o `charts/wordpress/CHANGELOG.md`):
   - Usare il formato [Keep a Changelog](https://keepachangelog.com/)
   - Sezioni: `Added`, `Changed`, `Fixed`, `Removed`, `Breaking Changes`
   - Per breaking changes: includere sempre una **Migration Guide**

3. **Aggiornare la versione in `Chart.yaml`** seguendo [Semantic Versioning](https://semver.org/):
   - **Major** (x.0.0): Breaking changes (modifiche incompatibili, rinominazione risorse, rimozione campi)
   - **Minor** (0.x.0): Nuove funzionalità retrocompatibili
   - **Patch** (0.0.x): Bug fix retrocompatibili

4. **Aggiornare `values.schema.json`** se si aggiungono o modificano campi in `values.yaml`.