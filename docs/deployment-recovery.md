# Reprendre un déploiement interrompu

Un contrôle HTTPS peut échouer après la création des conteneurs et des volumes, par exemple si le serveur résout encore l’ancienne adresse après une bascule DNS. Cela ne signifie pas que les ressources ont été annulées.

Le déploiement conserve alors le manifeste candidat et son fichier de version dans un répertoire `.deployment-recovery.<tag>.*` sous le répertoire applicatif. Le répertoire est privé (`700`), les fichiers sont privés (`600`). Ils peuvent contenir des paramètres sensibles et ne doivent être ni publiés, ni ajoutés à Git. Le jeton GHCR et le JSON Compose contenant les secrets résolus sont toujours nettoyés.

La version courante reste enregistrée uniquement après les vérifications de santé. La présence de ressources sans manifeste courant continue de bloquer les relances automatiques : le point de reprise sert à réconcilier l’état, pas à contourner ce garde-fou.

Avant de restaurer un manifeste :

1. Confirmer le tag et l’image immuables réellement exécutés, ainsi que l’état sain des services.
2. Comparer les variables, montages et réseaux du manifeste résolu avec les conteneurs existants, sans afficher les secrets.
3. Vérifier le DNS utilisé par le serveur et l’accès HTTPS public. Un appel avec `curl --resolve` vérifie l’origine et son certificat, mais ne prouve pas la propagation DNS. Une purge du cache local peut suffire après comparaison avec les serveurs DNS publics.
4. Restaurer le manifeste correspondant aux ressources observées, puis enregistrer la version seulement après validation publique.
5. Vérifier que le hook `/usr/local/lib/server-setup/backup-databases.sh` est installé et qu’une cible de sauvegarde valide existe avant de reprendre une mise à jour de production.
6. Relancer uniquement les jobs échoués. Retirer les fichiers de reprise privés après réconciliation et validation.

Ne pas supprimer les volumes, réinitialiser la base ou déplacer un tag pour rendre une relance possible. Une sauvegarde préalable doit rester vérifiée ; une configuration Drive absente ne doit pas être présentée comme une sauvegarde distante fonctionnelle.
