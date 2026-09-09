# GitHub Actions CI/CD

Les branches de travail exécutent la CI. Une release Git Flow finalisée porte un tag
`Vx.y.z` : QA, build des images preprod/prod, déploiement preprod puis validation de
l'environnement GitHub `production`. Utiliser les commandes `git flow` et configurer
`gitflow.prefix.versiontag` à `V` ; le tag est créé lors de `release finish`.

## Configuration GitHub

Créer les environnements `preprod` et `production`, avec un reviewer obligatoire
pour `production`. Chaque environnement contient uniquement :

| Type | Nom | Valeur |
| --- | --- | --- |
| Variable | `APP_PATH` | Chemin serveur absolu stable, par exemple `/srv/apps/myapp-preprod` |
| Variable | `APP_URL` | URL HTTPS publique ; le déploiement vérifie `/health` |
| Secret | `SSH_HOST` | Nom DNS ou IP exacte du serveur |
| Secret | `SSH_USER` | Utilisateur de déploiement |
| Secret | `SSH_PRIVATE_KEY` | Clé privée de connexion SSH |
| Secret | `SSH_KNOWN_HOSTS` | Ligne(s) de clés publiques d'hôte vérifiées |

Le nom Compose est calculé à partir du nom du dépôt en minuscules et de
l'environnement (`depot-preprod`, `depot-prod`). Le Makefile définit le service
`php` ; son image est résolue depuis les modules Compose avec les mêmes paramètres
que le build. Aucun `APP_NAME`, `COMPOSE_PROJECT_NAME`, `RELEASE_SERVICE` ou
`RELEASE_IMAGE` n'est à créer dans GitHub. Un renommage de dépôt change ce nom :
planifier alors la migration de l'identité Compose et de ses volumes.

### Vérifier et renseigner SSH_KNOWN_HOSTS

Depuis la console OVH ou une connexion dont l'identité est déjà vérifiée :

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Depuis votre machine, remplacer le nom ci-dessous par **exactement** `SSH_HOST` :

```bash
ssh-keyscan -t ed25519 serveur.example.fr > known_hosts
ssh-keygen -lf known_hosts
```

Comparer les empreintes avec celle relevée par le canal fiable. `ssh-keyscan` seul
n'authentifie pas le serveur. Si elles correspondent, copier le contenu intégral
de `known_hosts` dans `SSH_KNOWN_HOSTS`, par exemple :

```text
serveur.example.fr ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...
```

Il s'agit de la clé publique d'hôte, pas de l'empreinte ni de la clé privée SSH.
Les workflows utilisent le port SSH standard 22.

## Provisionnement serveur

Installer Docker Compose, Make, Python 3, `server-release` et le runtime de backup
Server-setup. Le compte SSH doit pouvoir exécuter Docker et la commande suivante
avec sudo sans mot de passe :

```bash
sudo /usr/local/lib/server-setup/backup-databases.sh
```

Provisionner hors CI, avant le premier déploiement :

```text
APP_PATH/secrets/postgres_password
APP_PATH/secrets/preprod.decrypt.private.php
```

En production, utiliser `prod.decrypt.private.php`. Ne jamais committer les clés
privées. Les fichiers doivent être lisibles par le compte de déploiement et par
l'utilisateur applicatif UID 33 à travers les montages Docker. Configurer ces droits
lors du provisionnement ; la CI contrôle les fichiers mais ne modifie ni leur
contenu ni leurs permissions. La base doit déjà utiliser ce même mot de passe.

Les secrets Docker sont des fichiers montés : Compose ne les génère pas. Aucun
secret PostgreSQL ou Symfony n'est transmis par GitHub. Une absence de fichier
interrompt le déploiement avant la modification de la stack.

## GHCR et restauration

Les jobs utilisent `github.actor` et le `GITHUB_TOKEN` automatique : permission
`packages: write` pour le build et `packages: read` pour le déploiement. Le package
GHCR doit autoriser ce dépôt. Aucun secret GHCR personnalisé n'est nécessaire.
Le serveur reçoit le jeton par le canal SSH, avec une configuration Docker
éphémère supprimée à la sortie du script. Il n'est pas conservé dans son login Docker.

Ce jeton expire avec le job : un pull ultérieur pour restauration nécessite une
authentification serveur provisionnée séparément, ou des images déjà disponibles.
Ne pas confondre cette configuration avec les secrets GitHub de déploiement.

## Contrat de déploiement

Les fichiers source Compose restent modulaires. Les commandes Compose sont
centralisées dans Make. Le déploiement travaille dans `APP_PATH` stable et utilise
`server-release init APP_PATH php IMAGE`, puis le backup avant la modification de
la stack. Le manifeste runtime résolu permet au runtime serveur de restaurer
l'image référencée par CURRENT/PREVIOUS. Seul un déploiement dont les healthchecks
internes et `/health` réussissent est enregistré par `server-release record`.

Le template ne fournit pas de stratégie de migration métier automatique. Ajouter
et tester celle du projet avant son premier déploiement comportant une migration.

```bash
make preprod-build IMAGE_TAG=V1.2.3
make preprod-push IMAGE_TAG=V1.2.3
make prod-build IMAGE_TAG=V1.2.3
make prod-push IMAGE_TAG=V1.2.3
```
