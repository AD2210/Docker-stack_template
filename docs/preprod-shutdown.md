# Arrêt de la préproduction après promotion

Variable GitHub **au niveau du dépôt**, dans Settings → Secrets and variables →
Actions → Variables : `STOP_PREPROD_AFTER_PROMOTION=true` pour activer l'arrêt.
Absente ou différente de `true`, elle conserve le comportement actuel.
Elle est indépendante de `ENABLE_DEPLOYMENT` et peut varier entre applications.

Le workflow `Promote production` ajoute un job après la réussite du déploiement
production, de ses contrôles de santé et de son enregistrement de release.
Une promotion échouée ou ignorée ne déclenche pas d'arrêt.
Le job utilise l'environnement GitHub `preprod` : ses variables `APP_PATH` et
ses cinq secrets SSH habituels, même si la production utilise un autre serveur.
Il partage le verrou `deploy-preprod` des déploiements pour éviter de les interrompre.

Le manifeste runtime et les images des conteneurs applicatifs doivent correspondre
exactement au tag promu. Une autre version, notamment une préprod plus récente,
est laissée en place. Une installation absente ne nécessite aucune action.
Une configuration incohérente ou un échec SSH/Docker fait échouer le job d'arrêt ;
la production déjà validée reste déployée, sans rollback automatique.

L'arrêt exécute `docker compose stop --timeout 30 php messenger scheduler` avec
le projet et le manifeste runtime de la préproduction. Le site et les workers
sont arrêtés ; l'URL préprod devient indisponible. PostgreSQL reste actif pour les
sauvegardes programmées et celles obligatoires avant les prochains déploiements.
Aucun conteneur, volume, document, secret, historique de release ou routage Caddy
n'est supprimé. Le prochain déploiement préprod redémarre les services.
Passer le flag à `false` ne redémarre pas une application déjà arrêtée.

Pour redémarrer manuellement, sur le serveur, dans `APP_PATH` :

```bash
docker compose --env-file .env.prod.local -f compose.runtime.yaml start php messenger scheduler
```

Le manifeste runtime conserve le nom du projet. Le fichier `.env.prod.local`
est celui tenu par `server-release`, y compris pour la préproduction.

Le tag promu doit contenir cette version du workflow et du script ; modifier
la branche principale ne change pas les tags déjà publiés. Préparer une nouvelle
release PATCH pour utiliser cette option. Le flag n'est pas activé par le code.
