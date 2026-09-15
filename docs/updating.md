# Updating Your Project

To import the changes made to the _Symfony Docker_ template into your project,
we recommend using [_template-sync_](https://github.com/coopTilleuls/template-sync):

1. Run the script to synchronize your project with the latest version of the skeleton:

   <!-- markdownlint-disable MD013 -->

   ```console
   curl -sSL https://raw.githubusercontent.com/coopTilleuls/template-sync/main/template-sync.sh | sh -s -- https://github.com/dunglas/symfony-docker
   ```

   <!-- markdownlint-enable MD013 -->

2. Resolve conflicts, if any
3. Run `git cherry-pick --continue`

For more advanced options, refer to [the documentation of _template sync_](https://github.com/coopTilleuls/template-sync#template-sync).


### Déploiement interrompu avec un job vert (entrée standard SSH)

Le script distant est envoyé à `bash -s`. Son corps est un bloc complet dont
l'entrée est redirigée depuis `/dev/null` : Bash lit tout le bloc avant son
exécution et les commandes enfants ne peuvent pas absorber la suite du script.
Le test de régression simule un `docker compose run` qui lit son entrée.
Un déploiement terminé doit afficher `Release ... recorded after successful readiness check.`

Les preuves de préprod utilisent désormais `preprod-v2-<tag>-<sha>` ; les preuves
antérieures ne permettent plus la promotion depuis le workflow corrigé.
Une ancienne release conserve son ancien workflow : utiliser une nouvelle release
contenant la correction et le workflow manuel de production à jour.

Si `Existing Docker resources without runtime manifest; reconciliation required`
apparaît, ne pas supprimer les volumes ni fabriquer un manifeste pour contourner
le contrôle. Relever les conteneurs et volumes du projet (remplacer le nom si besoin) :

```bash
docker ps -a --filter label=com.docker.compose.project=prospection-preprod
docker volume ls --filter label=com.docker.compose.project=prospection-preprod
```

Comparer cet inventaire aux logs du premier déploiement et vérifier les données
avant de choisir une reprise ou un nettoyage ciblé. Un job vert sans le message
final ne prouve pas que migrations, Caddy et contrôle HTTP ont été exécutés.
