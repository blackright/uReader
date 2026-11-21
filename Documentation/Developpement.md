# Développer uReader

## Installation

Depuis la racine du dépôt, exécuter `flutter doctor`, puis `flutter pub get`.
Configurer le SDK Android dans Android Studio et accepter ses licences avec
`flutter doctor --android-licenses` si nécessaire. Brancher un appareil ARM64 avec
le débogage USB autorisé, puis utiliser `flutter run -d <identifiant>`.

Le moteur Android dépend de `com.microsoft.onnxruntime:onnxruntime-android:1.25.0`.
Une installation standard récupère cet artefact depuis Maven Central. Un miroir
local audité peut être placé dans `validation/private/maven/` pour travailler sans
réseau ; ce miroir n’est pas distribué dans le dépôt.

## Ressources vocales

Le catalogue `assets/models/manifest.json` définit les fichiers exacts attendus,
leurs tailles, empreintes SHA-256, provenance et interfaces. Le moteur ne doit pas
accepter des poids de provenance ou d’interface différentes sous le même nom.

Le bundle comprend les graphes principal, flow et décodeur Mimi, les embeddings
texte et voix, le tokenizer et son manifeste d’exécution. Les poids et les WAV
ne sont pas versionnés. Pour installer un bundle compatible sur le téléphone,
utiliser le sélecteur de dossier de l’écran Voix.

Les scripts d’export, d’assemblage et de vérification sont conservés dans
`validation/scripts/`. Ils exigent des ressources et dépendances Python
supplémentaires ; ils ne sont pas exécutés par `flutter pub get` ou la compilation.
Ils constituent des outils de reproduction, pas un téléchargement automatique
ni une garantie qu’un bundle public prêt à installer soit disponible.

Le catalogue debug actuel active un alignement de développement. La précision
mot à mot n’est pas encore qualifiée. Le code distingue disponibilité de la
fonction et validation de sa précision ; conserver cette distinction.

## Vérifications

```bash
flutter analyze
flutter test --concurrency=1
flutter build apk --debug --target-platform android-arm64
```

Pour un parcours d’intégration préparé, utiliser par exemple :

```bash
flutter test integration_test/fluent_audio_test.dart -d <identifiant-android>
```

Cet essai joue des phrases synthétiques avec le vrai moteur et le vrai lecteur.
Il exige le bundle compatible installé, un appareil disponible et du temps pour
la synthèse. Il ne remplace pas une vérification de l’intelligibilité ou de
l’accessibilité. Ne pas lancer tous les laboratoires sur des données personnelles
sans lire leurs prérequis.

Les tests ZIP natifs peuvent nécessiter la génération de leurs ressources via
`validation/epub/scripts/prepare-android-fixtures.py`. Les autres scripts de
laboratoire documentent leurs arguments dans leur source ou leur option `--help`.
Certains anciens scripts de campagne contiennent une configuration d’appareil
locale : l’adapter avant utilisation.

## Données locales

Ne jamais résoudre un problème de lancement en supprimant les données de
l’application. Les imports, positions et signets appartiennent à l’utilisateur.
Préférer une mise à jour avec conservation des données, et une sauvegarde privée
avant une migration ou un essai qui les concerne.

Le `.gitignore` exclut les livres, poids, enregistrements, bases, captures, APK,
caches, secrets, rapports locaux et configuration des outils de développement.
Les outils de validation publiés peuvent créer ces fichiers localement ; ils
restent volontairement hors du dépôt.

## Livraison

La cible actuelle est Android ARM64. La configuration release utilise encore la
signature debug de développement ; préparer une vraie configuration de signature
avant toute distribution. La sécurité des versions de production, les pages
mémoire 16 Kio, les appareils supplémentaires et plusieurs recettes manuelles
restent à évaluer selon le périmètre de livraison retenu.
