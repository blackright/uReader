# Outils de vérification

Ce répertoire publie les sources des outils de reproduction, d’export vocal,
de génération de ressources synthétiques et de mesure.

- `scripts/` : exports Pocket TTS, assemblage et vérification des bundles.
- `epub/scripts/` : génération des EPUB synthétiques et contrôles d’import.
- `reader/scripts/` et `reader/tools/` : corpus, préservation des données et bancs audio.
- `protocols/` : critères et corpus de recette.

Les ressources privées, poids, enregistrements, rapports et captures ne sont pas
versionnés. Les scripts ne sont pas tous autonomes : lire leurs arguments et
prérequis avant exécution. Certains anciens scripts de campagne sont liés à une
configuration d’appareil et doivent être adaptés.

Consulter le [guide de développement](../Documentation/Developpement.md) pour les
commandes applicatives et les limites de validation.
