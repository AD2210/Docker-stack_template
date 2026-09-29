"""Contrat du manifeste de synchronisation avec le gabarit.

Le manifeste declare ce qu'un projet reprend du gabarit. Une entree qui ne
correspond a rien est une entree fausse : elle laisse la derive s'installer sans
que personne ne la voie, et la decouverte se fait un jour de deploiement casse,
sur une machine, a l'heure ou personne n'a le temps de la chercher.

Les verifications portent sur les trois directions :

- une entree reprise doit exister dans le gabarit, sinon la synchronisation echoue
  sur un chemin que le gabarit ne fournit plus, et l'echec n'apparait qu'a la
  premiere utilisation ;
- une entree `excluded` doit exister, sur disque cette fois. `vendor`, `var` et
  `secrets` sont ignores par git, donc presents sans etre versionnes, et c'est
  precisement pour cela qu'ils sont exclus : ils voyagent avec le gabarit et ne
  doivent surtout pas suivre. Chercher parmi les seuls fichiers versionnes les
  declarerait tous absents, et le controle echouerait en annonçant que le gabarit
  n'a pas de dossier de dependances alors qu'il en a un ;
- une entree `preserve` ne doit PAS exister dans le gabarit, parce que son but
  est de proteger un fichier du projet. Une entree qui vient a exister dans le
  gabarit signale que le gabarit l'a reclame, et que la protection doit disparaitre
  avant que la synchronisation n'ecrase le fichier.
"""

import pathlib
import subprocess
import unittest

import yaml

RACINE = pathlib.Path(__file__).resolve().parents[2]
MANIFESTE = RACINE / ".github/deploy-manifest.yaml"


def charger():
    with MANIFESTE.open(encoding="utf-8") as flux:
        return yaml.safe_load(flux)


def sur_disque(chemin):
    """Indique si le chemin existe dans l'arborescence, versionne ou non."""
    return (RACINE / chemin).exists()


class ManifesteSynchronisationTest(unittest.TestCase):
    def setUp(self):
        self.manifeste = charger()

    def test_le_manifeste_declenche_un_nombre_de_version(self):
        # Sans version, un projet deja synchronise ne peut pas dire s'il suit la
        # forme qu'il a synchronisee. Le champ sert moins a la migration qu'a la
        # possibilite de refuser un manifeste inconnu plutot que de le mal lire.
        self.assertIn("version", self.manifeste)
        self.assertEqual(1, self.manifeste["version"])

    def test_chaque_fichier_requis_existe_dans_le_gabarit(self):
        for entree in self.manifeste["files"]:
            with self.subTest(chemin=entree["path"]):
                self.assertTrue(
                    sur_disque(entree["path"]),
                    "%s est absent du gabarit" % entree["path"],
                )

    def test_chaque_fichier_implique_existe_dans_le_gabarit(self):
        for entree in self.manifeste["files_nested"]:
            with self.subTest(chemin=entree["path"]):
                self.assertTrue(
                    (RACINE / entree["path"]).is_file(),
                    "%s n'est pas un fichier du gabarit" % entree["path"],
                )

    def test_chaque_repertoire_existe_dans_le_gabarit(self):
        for entree in self.manifeste["directories"]:
            with self.subTest(chemin=entree["path"]):
                self.assertTrue(
                    (RACINE / entree["path"]).is_dir(),
                    "%s n'est pas un repertoire du gabarit" % entree["path"],
                )

    def test_chaque_exclusion_designe_un_chemin_reel(self):
        # Sur disque, et non parmi les fichiers versionnes : un chemin ignore
        # par git existe quand meme, et c'est ce qui rend son exclusion utile.
        for entree in self.manifeste["excluded"]:
            with self.subTest(chemin=entree["path"]):
                self.assertTrue(
                    sur_disque(entree["path"]),
                    "%s n'existe pas dans le gabarit, son exclusion ne sert a rien"
                    % entree["path"],
                )

    def test_chaque_preservation_designe_un_fichier_absent_du_gabarit(self):
        for entree in self.manifeste["preserve"]:
            with self.subTest(chemin=entree["path"]):
                self.assertFalse(
                    sur_disque(entree["path"]),
                    "%s existe dans le gabarit : la protection d'un fichier du "
                    "projet n'a plus lieu d'etre" % entree["path"],
                )

    def test_aucune_entree_ne_se_recoupe(self):
        # Un chemin a la fois copie et preserve est une contradiction silencieuse
        # : la synchronisation l'ecraserait en le protegeant. Un chemin a la fois
        # copie et exclu l'est aussi, et dans l'autre sens.
        repris = [
            e["path"]
            for e in self.manifeste["files"] + self.manifeste["files_nested"] + self.manifeste["directories"]
        ]
        exclus = [e["path"] for e in self.manifeste["excluded"]]
        preserves = [e["path"] for e in self.manifeste["preserve"]]

        for chemin in repris:
            self.assertNotIn(chemin, exclus, "%s est a la fois repris et exclu" % chemin)
            self.assertNotIn(chemin, preserves, "%s est a la fois repris et preserve" % chemin)

    def test_les_repertoires_repris_ne_contiennent_pas_de_fichier_de_secret(self):
        # Un secret versionne dans un repertoire repris partirait avec le
        # gabarit, vers tous les projets. `secrets/` est exclu par construit, et
        # le test le prouve plutot que de le constater.
        for entree in self.manifeste["directories"]:
            with self.subTest(repertoire=entree["path"]):
                self.assertNotEqual("secrets", entree["path"])

    def test_une_exclusion_operative_est_sous_un_repertoire_repris(self):
        # Exclure `docker/services/front` alors que `docker` est repris
        # recursivement ne sert a rien si la copie ignore l'exclusion : le
        # fichier vide part quand meme. Toute exclusion contenu dans un
        # repertoire repris doit donc etre reellement eliminable.
        repris = [e["path"] for e in self.manifeste["directories"]]
        exclus = [e["path"] for e in self.manifeste["excluded"]]

        for chemin in exclus:
            with self.subTest(chemin=chemin):
                if not self.contenu_dans(chemin, repris):
                    continue
                self.assertFalse(chemin.endswith("/"), "%s : barre finale" % chemin)

    def test_une_exclusion_hors_arborescence_reste_sans_effet(self):
        # L'inverse merite d'etre affirme aussi. `vendor`, `var` ou
        # `secrets` ne sont dans aucune arborescence reprise : ils ne partiraient
        # pas meme sans exclusion. Les declarer, c'est consigner une decision
        # Negative — « ne pas synchroniser ceci » — ce qui est utile le jour ou
        # le gabarit ajoute `vendor` a une arborescence reprise, mais ne doit pas
        # laisser croire qu'une exclusion agit aujourd'hui.
        repris = [e["path"] for e in self.manifeste["directories"]]
        exclus = [e["path"] for e in self.manifeste["excluded"]]

        for chemin in exclus:
            with self.subTest(chemin=chemin):
                if self.contenu_dans(chemin, repris):
                    continue
                motif = self.motif_de(chemin)
                self.assertTrue(
                    motif,
                    "%s n'est dans aucune arborescence reprise : son exclusion "
                    "est sans effet, le motif doit le dire" % chemin,
                )

    def contenu_dans(self, chemin, repris):
        """Indique si le chemin est contenu dans une arborescence reprise."""
        return any(chemin.startswith(arbre.rstrip("/") + "/") for arbre in repris)

    def motif_de(self, chemin):
        """Rend le motif d'une exclusion, ou une chaine vide."""
        for entree in self.manifeste["excluded"]:
            if entree["path"] == chemin:
                return entree.get("reason", "").strip()

        return ""

    def test_chaque_motif_est_ecrit(self):
        # Une exclusion sans motif est une exclusion que personne ne pourra
        # contester ni maintenir : le prochain qui synchronise ce chemin n'aura
        # aucune trace de la decision.
        for section in ("excluded", "preserve"):
            for entree in self.manifeste[section]:
                with self.subTest(section=section, chemin=entree["path"]):
                    motif = entree.get("reason", "").strip()
                    self.assertTrue(motif, "%s : %s sans motif" % (section, entree["path"]))


if __name__ == "__main__":
    unittest.main()
