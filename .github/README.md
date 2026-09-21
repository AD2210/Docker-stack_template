# GitHub Actions CI/CD

Par défaut, le template ne publie aucune image et ne déploie rien. Les tags
`Vx.y.z` déclenchent seulement la résolution du tag et la QA tant que la variable
de dépôt `ENABLE_DEPLOYMENT` ne vaut pas `true`.

Dans un projet créé depuis ce template et prêt à être déployé, créer la variable
de dépôt `ENABLE_DEPLOYMENT=true`. Les tags `Vx.y.z` déclenchent alors la QA, les
builds preprod/prod et uniquement le déploiement preprod. Après succès de la
préproduction et du build prod, le workflow conserve pendant 90 jours une preuve
liée au tag et au SHA exacts.

Pour promouvoir : **Actions → Promote production → Run workflow**, sélectionner
directement le **tag validé Vx.y.z**, puis lancer sans champ supplémentaire. Ce lancement constitue
la validation humaine. Le workflow vérifie que le tag appartient à main et qu'une
exécution Release réussie a produit sa preuve de préproduction pour le même SHA.
Il déploie l'image prod déjà construite, sans rebuild. Preprod et prod ont des
images distinctes car APP_ENV diffère, mais proviennent du même commit validé.
Une preuve absente, expirée, un tag déplacé ou une API indisponible bloque la promotion.
Les anciennes releases sans preuve ne sont pas promouvables par ce parcours.
Ne pas relancer les builds d'un tag déjà publié : préparer une nouvelle version PATCH.

Le workflow doit être présent sur main avant utilisation. Dans les restrictions
de l'environnement production, autoriser les tags `V*.*.*` : la référence de
l'exécution manuelle est désormais le tag sélectionné.
La préproduction doit autoriser les tags V*.*.* et main pour une relance manuelle.
Aucun Required reviewer payant n'est requis ; protéger les modifications des workflows
et réserver les droits de déclenchement aux personnes autorisées. Cette procédure
ne constitue pas une approbation indépendante d'un administrateur du dépôt.

## Configuration GitHub

Créer d'abord cette variable au niveau du dépôt :

| Type | Nom | Valeur |
| --- | --- | --- |
| Variable | `ENABLE_DEPLOYMENT` | `true` uniquement pour les projets réellement déployables |

Créer les environnements `preprod` et `production`. Chaque environnement contient uniquement :

| Type | Nom | Valeur |
| --- | --- | --- |
| Variable | `APP_PATH` | Chemin serveur absolu stable, par exemple `/srv/apps/myapp-preprod` |
| Variable | `APP_URL` | URL complète avec `https://`, par exemple `https://app-preprod.example.fr` ; le déploiement vérifie `/health` |
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

Après comparaison des empreintes, afficher la valeur à copier :

```bash
cat known_hosts
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

Installer Docker Compose, Make, jq, `server-release` et le runtime de backup
Server-setup. Le compte SSH doit pouvoir exécuter Docker et la commande suivante
avec sudo sans mot de passe :

```bash
sudo /usr/local/lib/server-setup/backup-databases.sh
```

Provisionner hors CI, avant le premier déploiement :

```text
APP_PATH/secrets/postgres_password
APP_PATH/secrets/mercure_jwt_secret
APP_PATH/config/secrets/preprod/preprod.decrypt.private.php
```

En production, utiliser `APP_PATH/config/secrets/prod/prod.decrypt.private.php`. Ne jamais committer les clés
privées. Les fichiers doivent être lisibles par le compte de déploiement et par
l'utilisateur applicatif UID 33 à travers les montages Docker. Configurer ces droits
lors du provisionnement ; la CI contrôle les fichiers mais ne modifie ni leur
contenu ni leurs permissions. La base doit déjà utiliser ce même mot de passe.

Les secrets Docker sont des fichiers montés : Compose ne les génère pas. Aucun
secret PostgreSQL, Mercure ou Symfony n'est transmis par GitHub. Une absence de
fichier interrompt le déploiement avant la modification de la stack. La clé
Mercure est injectée depuis `APP_PATH/secrets/mercure_jwt_secret` pendant le rendu
runtime ; utiliser une valeur aléatoire d'au moins 32 caractères sûrs, par exemple
`openssl rand -hex 32`.

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

## Dépannage de la première recette

Les noms sont sensibles aux fautes de frappe. Dans Settings → Environments →
**preprod**, créer les cinq entrées SSH dans **Environment secrets**, pas dans
Environment variables. Répéter la configuration pour **production**.
`SSH_KNOWN_HOSTS` se termine par un S ; un secret absent est transmis comme chaîne
vide. Un secret défini uniquement dans production ne configure pas preprod.

| Symptôme | Vérification |
| --- | --- |
| `Host key verification failed`, code 255 | `SSH_KNOWN_HOSTS` contient la sortie complète de `cat known_hosts`, pas `256 SHA256:… (ED25519)`, qui est uniquement l’empreinte. L’hôte et le port correspondent exactement à SSH_HOST et SSH_PORT. |
| Code 2 avant déploiement | APP_URL doit inclure `https://`, pas seulement le domaine. Le workflow contrôle aussi le port entier 1–65535. |
| Code 1 avant les opérations de déploiement | Vérifier `make` et `jq` dans le PATH du compte SSH ; les nouveaux scripts indiquent lequel manque. |
| `Missing or unreadable runtime secret` | Vérifier présence et droits sur APP_PATH/secrets/postgres_password, APP_PATH/secrets/mercure_jwt_secret et APP_PATH/config/secrets/ENV/ENV.decrypt.private.php. Ne pas afficher leur contenu dans les logs. |
| `Invalid runtime secret: mercure_jwt_secret` | Régénérer APP_PATH/secrets/mercure_jwt_secret avec une valeur sans retour ligne et d'au moins 32 caractères, par exemple `openssl rand -hex 32`. |

Sur le serveur, avec le compte utilisé par la CD :

```bash
command -v make
command -v jq
```

Si ces commandes manquent sur Debian/Ubuntu, les installer via le provisionnement
serveur (`sudo apt-get update` puis `sudo apt-get install make jq`).

Après correction d’un paramètre ou prérequis serveur, relancer uniquement le job
**Deploy preprod / Deploy preprod** échoué (ou les jobs échoués), sans relancer les
builds réussis : les images ont déjà été publiées et leurs tags sont immuables.
Une modification du code des workflows exige un nouveau tag PATCH ; relancer un
ancien tag reprend ses anciens scripts et leurs anciens messages d’erreur.
