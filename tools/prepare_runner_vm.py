"""Prepare cloud-init files for a dedicated VM; never creates a VM or registers a runner."""

import argparse
import base64
import json
import os
import pathlib
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ssh-public-key", required=True, type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "var/runner-vm")
    args = parser.parse_args()
    key = args.ssh_public_key.read_text().strip()
    parts = key.split()
    if (
        "\n" in key
        or len(parts) < 2
        or parts[0] not in {"ssh-ed25519", "ssh-rsa", "ecdsa-sha2-nistp256"}
    ):
        parser.error("Une clé SSH publique sur une seule ligne est obligatoire.")
    try:
        base64.b64decode(parts[1], validate=True)
    except ValueError:
        parser.error("La clé publique n’est pas encodée correctement.")
    if any((args.output / name).exists() for name in ["user-data", "meta-data"]):
        parser.error(
            "La configuration existe déjà ; choisir un autre répertoire pour une nouvelle VM."
        )
    args.output.mkdir(parents=True, exist_ok=True)
    template = (ROOT / "deploy/runner/cloud-init.yaml").read_text()
    files = {
        "user-data": template.replace("__SSH_PUBLIC_KEY__", json.dumps(key)),
        "meta-data": f"instance-id: dsn-ci-{uuid.uuid4()}\nlocal-hostname: dsn-ci\n",
    }
    for name, content in files.items():
        fd = os.open(args.output / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as file:
            file.write(content)
    print(f"Configuration VM préparée dans {args.output}. Aucun runner enregistré.")


if __name__ == "__main__":
    main()
