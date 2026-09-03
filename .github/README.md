# GitHub Actions CI/CD template

## Workflow

### Working branches

`feature/**`, `bugfix/**`, `hotfix/**`, `support/**` -> full CI only.

`develop` and `main` do not trigger duplicate CI runs.

### Release

A `vX.Y.Z` tag triggers one orchestrated release:

1. validate tag and main ancestry;
2. full QA;
3. build/push preprod and prod images using the project Makefile;
4. deploy preprod;
5. internal Docker healthchecks;
6. external `/health` check;
7. `server-release record` for preprod;
8. production GitHub Environment approval;
9. deploy production;
10. internal + external healthchecks;
11. `server-release record` for production.

The Git SEMVER tag is passed as `IMAGE_TAG` to the existing Make build mechanism.
`APP_ENV` and `IMAGES_PREFIX` stay managed by the project build configuration.

## GitHub Environments

Create:

- `preprod`
- `production`

Protect `production` with a required reviewer.

### Environment variables

- `APP_NAME` — application identifier understood by `server-release`, e.g. `myapp-preprod`
- `APP_PATH` — stable server directory, e.g. `/srv/apps/myapp-preprod`
- `COMPOSE_PROJECT_NAME` — Compose isolation name
- `APP_URL` — public URL used for `/health`
- `RELEASE_SERVICE` — service tracked by server-release, e.g. `php`
- `RELEASE_IMAGE` — GHCR image without tag, e.g. `ghcr.io/org/app-php-preprod`

### Environment secrets

- `SSH_HOST`
- `SSH_USER`
- `SSH_PRIVATE_KEY`
- `SSH_KNOWN_HOSTS`
- `GHCR_USERNAME`
- `GHCR_TOKEN`
- `POSTGRES_PASSWORD`
- `SYMFONY_DECRYPT_PRIVATE_KEY`

## server-release integration

The deployment does not create release directories or store images on the server.

Before deployment:

```bash
server-release init <app> <service> <image>
```

A temporary release env is generated with the target SEMVER tag. This allows Compose
to pull/start the candidate image without changing CURRENT/PREVIOUS.

Only after the external healthcheck succeeds:

```bash
server-release record <app> <service> <tag> <image>
```

The existing server runtime then moves CURRENT to PREVIOUS automatically.

## Server-setup database backup integration

The CD calls the runtime installed by `Server-setup` module `40_backup` directly:

```bash
sudo /usr/local/lib/server-setup/backup-databases.sh
```

This happens after `server-release init` and before `docker compose pull/up`.

The deployment does not pass application-specific arguments to the backup command.
The Server-setup runtime reads:

```text
/etc/server-setup/backup/backup.conf
/etc/server-setup/backup/targets.d/*.conf
```

and backs up every configured PostgreSQL target, including its existing checksum,
rclone and retention workflow.

The SSH deployment user therefore needs passwordless sudo permission for this
runtime (or an equivalent sudo policy already configured by Server-setup).

The historical variable names `*_SHA_CURRENT` / `*_SHA_PREVIOUS` are intentionally
kept for compatibility even though their values are now SEMVER tags.

## Makefile contract

The build workflow expects these targets:

```text
make preprod-build IMAGE_TAG=vX.Y.Z
make preprod-push  IMAGE_TAG=vX.Y.Z
make prod-build    IMAGE_TAG=vX.Y.Z
make prod-push     IMAGE_TAG=vX.Y.Z
```

If your current target names differ, only `_build.yaml` needs to be adjusted.
