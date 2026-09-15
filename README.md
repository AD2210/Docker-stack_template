# Docker Stack Template

Template Symfony 7.4 avec FrankenPHP, PostgreSQL, Messenger, Scheduler, Caddy et
CI/CD GitHub Actions. Il sert de base réutilisable pour démarrer un projet web.
Le dépôt template peut être releasé sans publier ni déployer ; les projets créés
depuis ce template activent explicitement la CD quand ils sont prêts.

## Fonctionnalités

- Stack Docker Compose modulaire par service dans `docker/services/`.
- Overrides séparés pour `dev`, `preprod` et `prod` dans `docker/override/`.
- Image PHP unique réutilisée par l'application HTTP, Messenger et Scheduler.
- Healthcheck HTTP `/health` utilisé par la CD après rechargement Caddy.
- Publication d'images GHCR immuables par tag `Vx.y.z`.
- Promotion production manuelle depuis un tag déjà validé en préproduction.
- Secrets runtime montés depuis le serveur, jamais intégrés aux images.

## Démarrage local

Créer le secret PostgreSQL local, puis lancer la stack de développement :

```bash
mkdir -p secrets
openssl rand -hex 32 > secrets/postgres_password
make dev-up
```

L'application écoute par défaut sur `http://127.0.0.1:8002`. Mailpit est inclus
en développement via `docker/services/mailer.yaml`.

Commandes utiles :

```bash
make dev-config
make dev-logs
make dev-down
make qa
```

## Structure

```text
docker/services/        Services Compose indépendants
docker/override/        Configuration propre à chaque environnement
docker/env/             Variables runtime versionnées par environnement
caddy/apps/             Entrées Caddy applicatives déployées par la CD
caddy/snippets/         Snippets locaux qui simulent le provisionnement serveur
.github/workflows/      CI, release et promotion production
.github/scripts/        Scripts shell testés par les tests qualité
docs/                   Notes de maintenance et procédures de promotion
```

Pour ajouter un service réutilisable, créer un fichier sous `docker/services/`,
puis l'inclure dans `compose.yaml` ou dans l'override de l'environnement concerné.
Garder les commandes opérationnelles dans `Makefile` afin que les workflows et le
serveur consomment la même source de vérité.

## Configuration par projet

À adapter au démarrage d'un nouveau projet :

- `COMPOSE_PROJECT_BASE` dans `Makefile` pour l'identité Compose locale.
- `SERVER_NAME`, `DATABASE_NAME` et `DATABASE_USER` dans `docker/env/*.env`.
- Les domaines dans `caddy/apps/*.caddy`.
- Le `name` et la `description` de `composer.json`.
- Les secrets Symfony et PostgreSQL provisionnés hors dépôt.

Les clés `config/secrets/preprod/*.decrypt.private.php` et
`config/secrets/prod/*.decrypt.private.php` doivent rester hors Git et être
créées sur le serveur dans `APP_PATH/config/secrets/<env>/`.

## Qualité

Avant commit ou release :

```bash
make check-compose
make check-caddy-frankenphp
composer validate --strict
vendor/bin/php-cs-fixer check --diff
vendor/bin/phpstan analyse
php bin/phpunit
python3 -m unittest discover -s tests/Quality -p "test_*.py"
```

`make qa` regroupe les checks principaux du projet. Les tests qualité couvrent le
contrat de promotion, le rendu du manifeste runtime et le rechargement Caddy.

## Release

Créer un tag stable `Vx.y.z`. Sur le dépôt template, le workflow `Release`
exécute la résolution du tag et la QA seulement.

Dans un projet réellement déployable, créer la variable de dépôt
`ENABLE_DEPLOYMENT=true`. Le même workflow construit alors les images `preprod`
et `prod`, déploie seulement la préproduction, puis conserve une preuve tag/SHA
pendant 90 jours.

La production se lance ensuite manuellement depuis le tag validé :

```bash
gh workflow run production.yaml --ref Vx.y.z
```

La procédure détaillée et les variables GitHub attendues sont documentées dans
[.github/README.md](.github/README.md). Les notes de reprise manuelle sont dans
[docs/manual-promotion.md](docs/manual-promotion.md) et
[docs/updating.md](docs/updating.md).
