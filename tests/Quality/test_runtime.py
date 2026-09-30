"""Contrat du rendu du manifeste d'execution.

`render-runtime.sh` ecrit le manifeste que `docker compose` lira sur le serveur. Il
ne connait pas les noms de services du projet : le projet les declare dans
`runtime.json`. Cette separation est le sujet de ces tests, parce que sa valeur
est invisible quand tout va bien et qu'elle ne se verrait pas du tout si le
nommage etait laisse dans le script.

Trois proprietes sont verifiees.

La premiere est que la declaration remplace une liste figee. Un projet qui nomme
ses services autrement que le gabarit doit obtenir un manifeste correct sans
modifier un script du gabarit, et un projet sans Mercure ne doit pas voir
apparaitre des variables Mercure dans son service principal.

La deuxieme est que chaque declaration fausse est refusee en nommant sa cause.
Le cas le plus important est l'oubli : un service absent de la declaration
conserve son image, et une chaine qui garde un worker sur une vieille version sans
le dire est l'echec que la declaration existe pour empecher. Le partage d'image
avec un service declare est la seule trace de cet oubli, et elle est verifiable.

La troisieme est que l'image reste interpolee dans le manifeste. Le manifeste est
ecrit avant le deploiement et relu au retour arriere : resoudre la valeur ici la
figerait dans un fichier qui doit pouvoir suivre un tag different.
"""

import json
import os
import pathlib
import subprocess
import tempfile
import unittest

import yaml

RACINE = pathlib.Path(__file__).resolve().parents[2]
RENDREUR = RACINE / ".github/scripts/render-runtime.sh"
DECLARATION = RACINE / ".github/scripts/runtime.json"

IMAGE_ATTENDUE = "${PHP_IMAGE:?Missing release image}:${PHP_SHA_CURRENT:?Missing release tag}"


def compose(mercure=True, services=("php", "messenger", "scheduler")):
    """Rend un Compose resolu plausible, dans la forme de `config --format json`."""
    document = {"name": "prospection-preprod", "services": {}}
    for nom in services:
        document["services"][nom] = {
            "image": "ghcr.io/example/app:V1.0.0",
            "build": {"context": "/app"},
        }

    if mercure:
        document["services"]["php"]["environment"] = {
            "MERCURE_JWT_SECRET": "!ChangeThisMercureHubJWTSecretKey!",
            "MERCURE_PUBLISHER_JWT_KEY": "!ChangeThisMercureHubJWTSecretKey!",
            "MERCURE_SUBSCRIBER_JWT_KEY": "!ChangeThisMercureHubJWTSecretKey!",
            "APP_ENV": "preprod",
        }

    document["services"]["database"] = {
        "image": "postgres:16-alpine",
        "environment": {"POSTGRES_DB": "dedicated"},
    }

    return document


class RenduTest(unittest.TestCase):
    def setUp(self):
        temporaire = tempfile.TemporaryDirectory()
        self.addCleanup(temporaire.cleanup)
        self.racine = pathlib.Path(temporaire.name)

    def rendre(self, document, declaration, environnement=None):
        """Rend le manifeste et rend le processus et le fichier produit."""
        entree = self.racine / "resolved.json"
        sortie = self.racine / "compose.runtime.yaml"
        contrat = self.racine / "runtime.json"

        self.ecrire(entree, document)
        self.ecrire(contrat, declaration)

        complet = dict(os.environ)
        for nom in ("MERCURE_JWT_SECRET", "SECRET_TEST"):
            complet.pop(nom, None)
        complet.update(environnement or {})

        processus = subprocess.run(
            ["bash", str(RENDREUR), str(entree), str(sortie), str(contrat)],
            capture_output=True,
            text=True,
            env=complet,
            check=False,
        )

        return processus, sortie

    def ecrire(self, chemin, contenu):
        chemin.write_text(contenu if isinstance(contenu, str) else json.dumps(contenu), encoding="utf-8")

    def lire(self, sortie):
        return json.loads(sortie.read_text(encoding="utf-8"))

    def declaration_du_gabarit(self):
        return json.loads(DECLARATION.read_text(encoding="utf-8"))


class RenduNominalTest(RenduTest):
    def test_le_gabarit_declara_obtient_son_manifeste(self):
        processus, sortie = self.rendre(
            compose(), self.declaration_du_gabarit(),
            {"MERCURE_JWT_SECRET": "un-secret-de-plus-de-32-caracteres"},
        )
        self.assertEqual(0, processus.returncode, processus.stderr)

        manifeste = self.lire(sortie)
        self.assertEqual("prospection-preprod", manifeste["name"])

        for nom in ("php", "messenger", "scheduler"):
            self.assertEqual(IMAGE_ATTENDUE, manifeste["services"][nom]["image"])
            self.assertNotIn("build", manifeste["services"][nom])

        # Un service tiers garde son image : la declaration dit ce qui porte la
        # version, elle ne dit pas ce qui doit disparaitre.
        self.assertEqual("postgres:16-alpine", manifeste["services"]["database"]["image"])

        # Une variable que la declaration ne cite pas reste intacte.
        self.assertEqual("preprod", manifeste["services"]["php"]["environment"]["APP_ENV"])

    def test_le_secret_est_verifie_mais_jamais_ecrit(self):
        """Le manifeste reste un fichier sans secret.

        Il est ecrit sur le serveur, il y reste entre deux deploiements, et un
        operateur peut le lire. Ecrire la valeur y mettrait un secret dans un
        fichier que rien ne borne, alors que compose lira plus tard le meme
        environnement candidat et saura la resoudre. Le controle sert donc a
        echouer tot, pas a transporter la valeur.
        """
        secret = "un-secret-qui-ne-doit-pas-apparaitre-dans-le-fichier"
        processus, sortie = self.rendre(
            compose(), self.declaration_du_gabarit(), {"MERCURE_JWT_SECRET": secret},
        )
        self.assertEqual(0, processus.returncode, processus.stderr)

        brut = sortie.read_text(encoding="utf-8")
        self.assertNotIn(secret, brut)

        environnement = self.lire(sortie)["services"]["php"]["environment"]
        for nom in ("MERCURE_JWT_SECRET", "MERCURE_PUBLISHER_JWT_KEY", "MERCURE_SUBSCRIBER_JWT_KEY"):
            self.assertEqual(
                "${MERCURE_JWT_SECRET:?Missing runtime secret MERCURE_JWT_SECRET}", environnement[nom],
            )


class RenduNommageTest(RenduTest):
    def test_un_projet_nomme_autrement_obtient_le_meme_manifeste(self):
        """Le nom vient du projet, et le script du gabarit n'est pas modifie."""
        processus, sortie = self.rendre(
            compose(mercure=False, services=("php", "worker", "consumer")),
            {"services": ["php", "worker", "consumer"]},
        )
        self.assertEqual(0, processus.returncode, processus.stderr)

        manifeste = self.lire(sortie)
        for nom in ("php", "worker", "consumer"):
            self.assertEqual(IMAGE_ATTENDUE, manifeste["services"][nom]["image"])
            self.assertNotIn("build", manifeste["services"][nom])

    def test_un_projet_sans_mercure_ne_recoit_aucune_variable_mercure(self):
        """Une variable ajoutee a un service qui ne l'a pas demandee est un defaut.

        Le gabarit imposait trois variables Mercure a tous les projets, y compris a
        ceux qui n'utilisent pas Mercure. Elles etaient ajoutees au service principal
        sans que rien ne les lise, et le projet ne pouvait pas les retirer.
        """
        processus, sortie = self.rendre(
            compose(mercure=False), {"services": ["php", "messenger", "scheduler"]},
        )
        self.assertEqual(0, processus.returncode, processus.stderr)

        self.assertNotIn("environment", self.lire(sortie)["services"]["php"])


class RenduRefusTest(RenduTest):
    def refuser(self, document, declaration, attendu, environnement=None):
        processus, _ = self.rendre(document, declaration, environnement)
        self.assertNotEqual(0, processus.returncode, "le rendu aurait dû échouer")
        self.assertIn(attendu, processus.stderr)

    def test_un_service_absent_du_compose_est_refuse(self):
        self.refuser(compose(), {"services": ["php", "absent"]},
            "names a service the Compose file does not have: absent")

    def test_une_liste_vide_est_refusee(self):
        self.refuser(compose(), {"services": []}, '"services" must be a non-empty array')

    def test_une_erreur_de_frappe_dans_une_variable_est_refusee(self):
        declaration = {
            "services": ["php", "messenger", "scheduler"],
            "environment": {"php": {"MERCURE_JWTSECRET": "MERCURE_JWT_SECRET"}},
        }
        self.refuser(compose(), declaration, "writes a variable php does not declare: MERCURE_JWTSECRET")

    def test_un_secret_absent_de_l_environnement_est_refuse(self):
        declaration = {
            "services": ["php", "messenger", "scheduler"],
            "environment": {"php": {"MERCURE_JWT_SECRET": "MERCURE_JWT_SECRET"}},
        }
        self.refuser(compose(), declaration, "needs the environment variable MERCURE_JWT_SECRET")

    def test_un_secret_vide_est_refuse(self):
        declaration = {
            "services": ["php", "messenger", "scheduler"],
            "environment": {"php": {"MERCURE_JWT_SECRET": "MERCURE_JWT_SECRET"}},
        }
        self.refuser(compose(), declaration, "needs the environment variable MERCURE_JWT_SECRET",
            {"MERCURE_JWT_SECRET": ""})

    def test_une_declaration_illisible_est_refusee(self):
        processus, _ = self.rendre(compose(), "{")
        self.assertNotEqual(0, processus.returncode)
        self.assertIn("Bad JSON", processus.stderr)

    def test_une_declaration_absente_est_refusee(self):
        processus = subprocess.run(
            [
                "bash", str(RENDREUR),
                str(self.racine / "resolved.json"),
                str(self.racine / "compose.runtime.yaml"),
                str(self.racine / "absent.json"),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(1, processus.returncode)
        self.assertIn("Missing or unreadable runtime declaration", processus.stderr)

    def test_un_service_oublie_mais_partageant_l_image_est_refuse(self):
        """L'oubli est le seul defaut que la declaration ne peut pas voir seule.

        Un service non declare garde son image, sans erreur et sans trace. Le
        partage d'image avec un service declare est la seule trace disponible : dans
        un Compose, deux services sans lien ne recoivent pas la meme image par
        hasard. Le refus vaut donc mieux qu'un deploiement partiel.
        """
        self.refuser(compose(), {"services": ["php"]}, "omits messenger, which runs the same image")

    def test_un_service_tiers_non_declare_passe(self):
        """`database` ne partage aucune image : ne pas le declarer est normal."""
        processus, sortie = self.rendre(compose(), {"services": ["php", "messenger", "scheduler"]})
        self.assertEqual(0, processus.returncode, processus.stderr)
        self.assertEqual("postgres:16-alpine", self.lire(sortie)["services"]["database"]["image"])

    def test_une_cible_inconnue_dans_environment_est_refusee(self):
        declaration = {"services": ["php"], "environment": {"absent": {"MERCURE_JWT_SECRET": "MERCURE_JWT_SECRET"}}}
        self.refuser(compose(), declaration, "names a service the Compose file does not have: absent")


class DeclarationGabaritTest(unittest.TestCase):
    """La declaration livree doit decrire le Compose livre.

    Le fichier est repris tel quel par chaque projet. S'il nomme un service que le
    Compose du gabarit n'a pas, le premier deploiement du gabarit echoue, et le
    message parlera d'un nom que personne n'a jamais vu ailleurs.
    """

    def services_inclus(self):
        assemblage = yaml.safe_load((RACINE / "compose.yaml").read_text(encoding="utf-8"))

        services = {}
        for chemin in assemblage["include"]:
            document = yaml.safe_load((RACINE / chemin).read_text(encoding="utf-8")) or {}
            services.update(document.get("services", {}))

        return services

    def test_la_declaration_nome_seulement_des_services_inclus(self):
        services = self.services_inclus()
        declaration = json.loads(DECLARATION.read_text(encoding="utf-8"))

        for nom in declaration["services"]:
            self.assertIn(nom, services, f"{nom} est declare mais absent du Compose assemble")

    def test_la_declaration_n_ecrit_que_des_variables_declarees(self):
        services = self.services_inclus()
        declaration = json.loads(DECLARATION.read_text(encoding="utf-8"))

        for nom, variables in declaration.get("environment", {}).items():
            declarees = services.get(nom, {}).get("environment", {})
            for variable in variables:
                self.assertIn(variable, declarees, f"{nom}.{variable} n'est pas declare par le Compose")


if __name__ == "__main__":
    unittest.main()
