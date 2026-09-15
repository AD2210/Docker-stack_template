# Promotion manuelle par tag

Dans Actions → Promote production → Run workflow, utiliser la référence du tag
`Vx.y.z` à promouvoir. Le workflow utilise directement `github.ref_name` : aucun
champ de tag supplémentaire. Une exécution sur une branche est ignorée.

Le tag doit contenir cette version du workflow ; les tags historiques conservent
leur ancien formulaire. Le commit doit appartenir à `origin/main` et disposer
d'une preuve préprod valide pour son SHA exact. Git Flow reste le processus de
création des tags ; la vérification d'ascendance protège aussi des erreurs manuelles.

Le déclenchement par CLI accepte également directement la référence :

```bash
gh workflow run production.yaml --ref Vx.y.z
```

Remplacer `Vx.y.z` par le tag souhaité. Cette commande lance réellement la promotion.
La production utilise l'image déjà construite et validée par la préprod.

Les scripts de build et déploiement utilisent Bash et jq pour les données JSON.
Sur le serveur, vérifier `command -v jq` avant la prochaine release ; sur Debian ou
Ubuntu, si nécessaire : `sudo apt-get install jq`. Python n'est plus nécessaire au
déploiement ; certains tests locaux/CI l'utilisent encore.
