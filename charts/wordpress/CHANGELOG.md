# Changelog

## [1.1.0] - 2026-10-22

### Fixed
- **Salt keys preservate tra un upgrade e l'altro**: `{release}-salt-keys` riusa le chiavi già presenti nel Secret (`lookup`). Prima ogni `helm upgrade` generava 8 chiavi casuali nuove e disconnetteva tutti gli utenti. Priorità: `wordpress.saltKeys.*` > Secret esistente > random (solo alla prima installazione).

- `ingress.groupName` con default `frontend-public` nel template: con `--reuse-values` da release 0.5.x il valore mancava e l'annotation `group.name` diventava vuota, spostando l'Ingress fuori dall'ALB condiviso.

### Added
- `readinessProbe` (attiva di default): `httpGet` su `/wp-login.php`, porta `http`, header `X-Forwarded-Proto: https`. Il pod diventa ready solo quando Apache+PHP rispondono (l'entrypoint esegue wp-cli e gli script di init per ~1 min prima di avviare Apache). Configurabile con `readinessProbe.{enabled,path,initialDelaySeconds,periodSeconds,timeoutSeconds,failureThreshold}`.

### Changed
- `image.tag` di default → `7.1.3-php8.3-r2` (PHP 8.3.36, CVE-2026-109618/109619; worker Apache dimensionati sul limite di memoria).

### Note di upgrade
- Il primo upgrade a 1.1.0 mantiene le chiavi già presenti nel Secret: nessuna disconnessione.
- Con `--reuse-values` i nuovi default non vengono uniti: il template usa comunque gli stessi default, quindi la `readinessProbe` è attiva. Per prendere anche il nuovo default di `image.tag` usare `--reset-then-reuse-values`.
- Le release ancora su 0.5.x ricevono anche le modifiche della 1.0.0 (securityContext, Secret SFTP): verificare il diff con `--dry-run=server`.

## [1.0.0] - 2026-02-07

### Breaking Changes
- **SFTP credentials migrati da ConfigMap a Secret**: Il file `users.conf` con le credenziali SFTP viene ora gestito tramite un Secret Kubernetes invece che un ConfigMap. Se hai installazioni esistenti con SFTP abilitato, il ConfigMap `{release}-sftp` deve essere eliminato manualmente prima dell'upgrade.
- **`preventRoot: false` non forza più root**: Con `preventRoot: false` non viene applicato alcun securityContext, il container usa il USER dell'immagine (www-data/1000). Prima veniva forzato `runAsUser: 0` che causava il crash dell'entrypoint WordPress.

### Added
- Supporto `sftp.existingSecret` per utilizzare un Secret esterno per le credenziali SFTP
- Supporto `deployment.existingConfigMapsEnv` per montare ConfigMap come variabili d'ambiente
- Supporto `deployment.existingSecretsEnv` per montare Secret come variabili d'ambiente
- Supporto `wordpress.configExtraCM` e `wordpress.configExtraKey` per configurare `WORDPRESS_CONFIG_EXTRA` da un ConfigMap esterno
- Container SFTP ora ha `securityContext: runAsUser: 0` esplicito (necessario per gestione utenti SSH)

### Changed
- Gestione securityContext riscritta per supportare correttamente le combinazioni `preventRoot`/`sftp.enabled`
- Pod securityContext con `fsGroup` applicato quando SFTP è abilitato (per permessi volume condiviso)

### Migration Guide

1. **Se usi SFTP**: elimina il vecchio ConfigMap prima dell'upgrade:
   ```bash
   kubectl delete configmap {release-name}-sftp -n {namespace}
   ```
2. **Se usi `preventRoot: false`**: nessuna azione richiesta, ora funziona correttamente.
3. **Se vuoi usare un Secret esterno per SFTP**:
   ```yaml
   sftp:
     enabled: true
     existingSecret: "my-sftp-secret"   # Secret con chiave 'users.conf'
   ```