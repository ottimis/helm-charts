# Changelog

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