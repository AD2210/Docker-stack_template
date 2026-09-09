# GitHub Actions CI/CD

Les tags `Vx.y.z` déclenchent la QA, les builds preprod/prod et uniquement le
déploiement preprod. Après succès de la préproduction et du build prod, le workflow
conserve pendant 90 jours une preuve liée au tag et au SHA exacts.

Pour promouvoir : **Actions → Promote production → Run workflow**, sélectionner
la branche **main**, renseigner le tag validé puis lancer. Ce lancement constitue
la validation humaine. Le workflow vérifie que le tag appartient à main et qu'une
exécution Release réussie a produit sa preuve de préproduction pour le même SHA.
Il déploie l'image prod déjà construite, sans rebuild. Preprod et prod ont des
images distinctes car APP_ENV diffère, mais proviennent du même commit validé.
Une preuve absente, expirée, un tag déplacé ou une API indisponible bloque la promotion.
Les anciennes releases sans preuve ne sont pas promouvables par ce parcours.
Ne pas relancer les builds d'un tag déjà publié : préparer une nouvelle version PATCH.

Le workflow doit être présent sur main avant utilisation. Dans les restrictions
de l'environnement production, autoriser **la branche main** : la référence de
l'exécution manuelle est main, même si l'image déployée utilise un tag Vx.y.z.
La préproduction doit autoriser les tags V*.*.* et main pour une relance manuelle.
Aucun Required reviewer payant n'est requis ; protéger les modifications des workflows
et réserver les droits de déclenchement aux personnes autorisées. Cette procédure
ne constitue pas une approbation indépendante d'un administrateur du dépôt.

## Configuration GitHub

Créer les environnements `preprod` et `production`. Chaque environnement contient uniquement :

| Type | Nom | Valeur |
| --- | --- | --- |
| Variable | `APP_PATH` | Chemin serveur absolu stable, par exemple `/srv/apps/myapp-preprod` |
| Variable | `APP_URL` | URL HTTPS publique ; le déploiement vérifie `/health` |
| Secret | `SSH_HOST` | Nom DNS ou IP exacte du serveur |
| Secret | `SSH_PORT` | Port SSH obligatoire, entier de 1 à 65535 (22 si standard) |
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
ssh-keyscan -T 10 -p 2222 -t ed25519 serveur.example.fr > known_hosts
ssh-keygen -lf known_hosts
```

Comparer les empreintes avec celle relevée par le canal fiable. `ssh-keyscan` seul
n'authentifie pas le serveur. Si elles correspondent, copier le contenu intégral
de `known_hosts` dans `SSH_KNOWN_HOSTS`, par exemple :

```text
[serveur.example.fr]:2222 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...
```

Il s'agit de la clé publique d'hôte, pas de l'empreinte ni de la clé privée SSH.
Remplacer `2222` par la valeur de `SSH_PORT`. Pour un port personnalisé, conserver la ligne complète `[hôte]:port` produite par `ssh-keyscan`. Les workflows utilisent `ssh -p` et `scp -P` avec ce même secret.

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
APP_PATH/config/secrets/preprod/preprod.decrypt.private.php
```

En production, utiliser `APP_PATH/config/secrets/prod/prod.decrypt.private.php`. Ne jamais committer les clés
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

## Configuration Caddy applicative

La CD copie automatiquement Compose, le Makefile, le `.env` versionné, les fichiers
d’environnement et le fichier Caddy de l’environnement (`preprod.caddy` ou `app.caddy`).
Les secrets restent hors bundle. La clé privée suit le chemin Symfony standard
`APP_PATH/config/secrets/<env>/<env>.decrypt.private.php` (secrets au pluriel).

Server-setup installe le Caddyfile global et les snippets partagés `security` et
`logging`. La CD ne remplace pas ces fichiers serveur : leurs mises à jour relèvent
du provisionnement. Elle installe uniquement `/etc/caddy/apps/<nom-compose>.caddy`,
sous verrou global, valide la configuration complète puis recharge Caddy avant
le contrôle HTTP. En cas d'échec, elle restaure le fichier précédent et tente son
rechargement. Aucune unité systemd ne change, donc aucun daemon-reload.

Le compte de déploiement doit pouvoir exécuter sans interaction `sudo -n bash
APP_PATH/deploy/update-caddy.sh ...` (le compte administrateur Server-setup possède
ce droit). Caddy et flock doivent être installés. Les fichiers d'app déjà copiés
manuellement doivent être regroupés sous ce même nom pour éviter deux définitions
du même domaine. Renseigner les domaines dans les fichiers Caddy avant publication.

Première installation : sans manifeste, sans release enregistrée et sans conteneur
ou volume Docker du projet, la CD initialise la stack sans appeler le backup global.
Si une trace d'installation existe sans manifeste, elle s'arrête pour diagnostic.
Pour une stack existante, le backup global reste obligatoire et toute erreur bloque
le déploiement, y compris une erreur provenant d'une autre cible du serveur.
