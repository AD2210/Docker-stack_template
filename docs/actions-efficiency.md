# Git Flow, coûts Actions et runner dédié

## Déclenchements

Le fonctionnement normal est Git Flow, avec fusion locale puis poussée des branches. La CI n’exige et ne déclenche aucune PR.

- `feature/*`, `bugfix/*`, `hotfix/*`, `support/*`, `release/*` et `develop` : un contrôle rapide au push, avec annulation de l’exécution précédente de la même branche.
- Documentation seule (`docs/**`, README, changelog, licence) : aucun job automatique. Un commit de notes de version ne relance pas les tests.
- `main` : pas de deuxième CI automatique après une fusion. Le tag reste le point de validation complète du commit stable.
- Tag stable `Vx.y.z` : contrôles complets obligatoires avant construction et livraison en préproduction. Les E2E et audits de navigateur d’un projet doivent être raccordés au profil `full` lorsqu’ils sont disponibles.
- Production : promotion manuelle du même tag avec sa preuve de préproduction ; aucune reconstruction ni nouvelle validation complète.
- Le lancement manuel de CI permet de demander `full_validation` pour vérifier un candidat avant de poser un tag.

Les contrôles rapides regroupent analyse et tests dans un seul job, avec une installation Composer commune. Compose et Caddy sont vérifiés seulement si l’infrastructure a changé ou pour une validation complète. Une base Git inconnue active ces contrôles par précaution. La CI rapide ne construit pas d’image Docker jetable : les images réellement livrées sont construites par `_build.yaml`.

## Caches et artefacts

Composer conserve ses téléchargements ; PHPStan dispose d’un cache limité à `var/phpstan`, sans base de données ni secret applicatif. Chaque installation reste déterminée par son fichier de verrouillage. Un projet qui ajoute des étapes Node peut activer le cache npm de `actions/setup-node` et conserver une installation avec `npm ci`.

La release active `docker/override/build-cache.yaml` via `BUILD_CACHE_REF`. BuildKit importe et exporte un cache GHCR distinct des tags de release, par dépôt et environnement (`…-build-cache:preprod` et `…-build-cache:prod`). Le premier build remplit le cache ; les suivants peuvent réutiliser les couches. Le cache local de téléchargement Composer est également activé pendant la construction.

Le cache est absent des manifestes de déploiement et reste facultatif en local. Les images préproduction et production restent distinctes : le Dockerfile embarque actuellement un `APP_ENV` différent. Les fusionner demanderait une évolution séparée de la configuration de l’image.

Les petites preuves de promotion gardent leur rétention de 90 jours. Les rapports navigateur ajoutés par un projet peuvent avoir une rétention courte, par exemple sept jours. Les jobs ont un délai maximal explicite. Une erreur de qualité empêche les builds, et une préproduction non validée empêche la promotion.

## Runner sur une VM du poste

Profil initial proposé : Ubuntu Server 24.04 LTS, 4 vCPU, 8 Gio de RAM, disque de 120 Gio, réseau NAT et Docker à l’intérieur de la VM. Un seul agent, dédié au dépôt pour commencer, évite les collisions de ports entre les services des jobs. La VM doit être allumée pour exécuter les tâches ; les jobs restent en attente lorsqu’elle est arrêtée.

Le générateur prépare des fichiers cloud-init sans créer de VM ni installer d’agent sur le poste :

```bash
ssh-keygen -t ed25519 -f ~/.ssh/dsn-ci-vm -C dsn-ci-vm
python3 tools/prepare_runner_vm.py --ssh-public-key ~/.ssh/dsn-ci-vm.pub
```

Depuis le poste hôte, créer la VM dans libvirt/virt-manager avec une image cloud Ubuntu 24.04 vérifiée, puis lui fournir les fichiers NoCloud `var/runner-vm/user-data` et `meta-data`. Le profil installe les outils de base et Docker depuis son dépôt officiel. L’utilisateur de VM est `gha`, avec la clé publique fournie. Aucun jeton GitHub ni identifiant de production n’est enregistré dans ces fichiers. Le script refuse une clé privée et refuse d’écraser une configuration existante.

Après connexion SSH à la VM :

1. Dans GitHub, ouvrir le dépôt → Settings → Actions → Runners → New self-hosted runner → Linux x64.
2. Exécuter dans la VM, sous `gha`, les commandes de téléchargement et de vérification affichées par GitHub. Le lien et la version du runner sont ceux de cette page.
3. Exécuter `sudo ./bin/installdependencies.sh` si demandé. Configurer le runner avec le jeton temporaire et ajouter le label `dsn-ci`.
4. Installer le service avec `sudo ./svc.sh install gha`, puis `sudo ./svc.sh start`. Vérifier que le runner est « Idle » dans GitHub.
5. Créer la variable de dépôt **ACTIONS_RUNNER** avec la valeur JSON suivante :

```json
["self-hosted", "linux", "x64", "dsn-ci"]
```

Tous les jobs, y compris construction et déploiement, suivent cette variable. La laisser absente conserve `ubuntu-latest` ; il est aussi possible d’utiliser la chaîne JSON `"ubuntu-latest"`. Ne changer cette variable qu’une fois la VM en ligne. Il n’y a pas de bascule automatique vers un runner payant lorsque la VM est arrêtée.

Les clés SSH des livraisons sont créées sous `RUNNER_TEMP` et retirées en fin de job, même après un échec. Les sauvegardes, clés Google et autres secrets de production ne sont pas copiés dans la VM : seuls les secrets nécessaires au job lui sont transmis par GitHub.

Un runner de dépôt personnel est rattaché à ce dépôt. Pour partager un seul agent entre plusieurs dépôts, une organisation et ses runners partagés constituent une option ; sinon, prévoir des agents/VM et des ports isolés. Lancer plusieurs agents sur la même VM avec les ports fixes des tests provoquerait des collisions.

## Validation et limites

Les changements sont testables sans lancer de workflow : tests de sélection des fichiers, résolution Compose avec/sans cache, exécution isolée de la préparation SSH et génération cloud-init, puis contrôle des définitions avec actionlint. L’efficacité du cache distant et le gain réel seront mesurés au premier build autorisé.

Une modification de workflow ne change pas les tags existants. Pour qu’une release utilise le runner configurable, son tag doit inclure ces workflows. Conserver les anciens tags immuables et préparer une nouvelle version plutôt que de déplacer un tag déjà publié.

Sources : [cache de registre Docker](https://docs.docker.com/build/cache/backends/registry/), [installation Docker Ubuntu](https://docs.docker.com/engine/install/ubuntu/), [runners auto-hébergés](https://docs.github.com/en/actions/concepts/runners/self-hosted-runners), [ajout d’un runner](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners).
