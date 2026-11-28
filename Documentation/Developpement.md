# Développer uReader

## Installation

Le [README](../README.md#démarrer-le-projet) fournit le parcours de premier
lancement et de lecture visuelle. Pour proposer un changement, suivre aussi
[CONTRIBUTING.md](../CONTRIBUTING.md).

Depuis la racine du dépôt, exécuter `flutter doctor`, puis `flutter pub get`.
Configurer le SDK Android dans Android Studio et accepter ses licences avec
`flutter doctor --android-licenses` si nécessaire. Brancher un appareil ARM64 avec
le débogage USB autorisé, puis utiliser `flutter run -d <identifiant>`.

Le moteur Android dépend de `com.microsoft.onnxruntime:onnxruntime-android:1.25.0`.
Une installation standard récupère cet artefact depuis Maven Central. Un miroir
local audité peut être placé dans `validation/private/maven/` pour travailler sans
réseau ; ce miroir n’est pas distribué dans le dépôt.

Le wrapper utilise Gradle 9.3.1 et le fichier de critères du daemon configure
Java 25, avec des URL de provisioning par plateforme. Ne pas confondre cette JVM
avec la cible Java 17 du code Android. Prévoir un accès réseau lors de la première
configuration ; si le provisioning échoue, relever l’erreur et vérifier le JDK,
le proxy et les fichiers versionnés avant de modifier la configuration.

## Ressources vocales

Le profil de développement par défaut est désormais Kokoro SIWIS. Son catalogue
`assets/models/kokoro-manifest.json` décrit cinq fichiers :

```text
uReader-voice-kokoro/
  kokoro.onnx
  siwis.f32
  vocab.json
  tokenizer.json
  espeak-data.zip
```

Il fonctionne uniquement en développement et requiert le frontend natif ci-dessous.
`assets/models/kokoro-evidence.json` conserve les limites de la preuve Samsung ;
un verdict de banc natif ne devient pas une qualification G0 ou une recette sonore
de vingt minutes. Il n'existe pas de téléchargement public du bundle dérivé exact.
Les outils d'export et d'assemblage sont dans `validation/reader/scripts/` ; ils
nécessitent les poids locaux vérifiés et un environnement Python préparé.

### Frontend Kokoro Android

Dans SDK Manager, installer CMake **3.22.1** et le NDK demandé par la version Flutter
utilisée (configuration vérifiée : NDK **28.2.13676358**). La source eSpeak doit
correspondre à **4870adfa25b1a32b4361592f1be8a40337c58d6c**, version 1.52.0.
Le tag ultérieur 1.52.0.1 ne reproduit pas toutes les prononciations de référence.
Gradle ne télécharge pas cette dépendance automatiquement.

Depuis la racine, sous PowerShell, pour préparer cette source publique :

```powershell
$sourceVoix = 'validation/reader/private/espeak-4870adf-source'
New-Item -ItemType Directory -Path $sourceVoix -Force | Out-Null
Invoke-WebRequest 'https://codeload.github.com/espeak-ng/espeak-ng/zip/4870adfa25b1a32b4361592f1be8a40337c58d6c' -OutFile "$sourceVoix/source.zip"
if ((Get-FileHash "$sourceVoix/source.zip" -Algorithm SHA256).Hash -ine '096f0915470c3bba4f9e3ba274485e453f26dedccb5c28a33f871a84f5e064a9') {
    throw 'Archive eSpeak non conforme'
}
Expand-Archive -LiteralPath "$sourceVoix/source.zip" -DestinationPath $sourceVoix
flutter run -d IDENTIFIANT_ANDROID
```

Le build détecte ce dossier épinglé. Un autre emplacement peut être indiqué à
Gradle par `-PureaderEspeakSource=<chemin>` ; le build vérifie la révision attendue.
Ne remplacez pas les données phonétiques du bundle par celles d'une autre version.
Les notices eSpeak et Kokoro sont dans `assets/models/KOKORO_NOTICES.txt` ; revoir
les obligations de distribution du frontend avant publication d'un APK.

### Profil Pocket historique

Le catalogue `assets/models/manifest.json` définit les fichiers exacts attendus,
leurs tailles, empreintes SHA-256, provenance et interfaces. Le moteur ne doit pas
accepter des poids de provenance ou d’interface différentes sous le même nom.

Ce profil, sélectionné par `--dart-define=UREADER_SPEECH_PROFILE=pocket`, attend
ces sept fichiers au même niveau :

```text
uReader-voice-fr/
  flow_lm_main_int8.onnx
  flow_lm_flow_int8.onnx
  mimi_decoder_int8.onnx
  text_embeddings.f16
  tokenizer.json
  estelle.f16
  manifest.json
```

Le dernier fichier est le manifeste d’exécution fourni avec les graphes ; le
catalogue embarqué de l’application n’est pas un substitut. Les poids et les WAV
ne sont pas versionnés. Il n’existe pas encore de téléchargement public vérifié
du paquet exact documenté : voir [l’issue #16](https://github.com/blackright/uReader/issues/16).
Les ressources amont indiquées par le catalogue ne sont pas nécessairement les
sept fichiers dérivés prêts à installer.

Si le paquet est déjà disponible, ses tailles et SHA-256 peuvent être contrôlés
sous PowerShell, depuis la racine du projet. Remplacer le chemin du dossier :

```powershell
$catalogue = Get-Content assets/models/manifest.json -Raw | ConvertFrom-Json
$dossierVoix = 'C:\chemin\vers\uReader-voice-fr'
foreach ($entree in $catalogue.files) {
    $fichierVoix = Join-Path $dossierVoix $entree.relativePath
    if (-not (Test-Path -LiteralPath $fichierVoix -PathType Leaf)) {
        throw "Fichier manquant : $($entree.relativePath)"
    }
    $taille = (Get-Item -LiteralPath $fichierVoix).Length
    $empreinte = (Get-FileHash -LiteralPath $fichierVoix -Algorithm SHA256).Hash
    if ($taille -ne $entree.byteSize -or $empreinte -ine $entree.sha256) {
        throw "Fichier incompatible : $($entree.relativePath)"
    }
}
"$($catalogue.files.Count) fichiers vérifiés"
```

Ce contrôle compare les fichiers au catalogue ; il ne remplace ni la validation
de qualité de la voix ni la qualification de l’alignement. Transférer ensuite le
sous-dossier sur le téléphone et le sélectionner dans **Voix → Installer depuis
un dossier**. L’installateur vérifie aussi les fichiers avant publication.


Les scripts d’export, d’assemblage et de vérification sont conservés dans
`validation/scripts/`. Ils exigent des ressources et dépendances Python
supplémentaires ; ils ne sont pas exécutés par `flutter pub get` ou la compilation.
Ils constituent des outils de reproduction, pas un téléchargement automatique
ni une garantie qu’un bundle public prêt à installer soit disponible.

Le catalogue debug actuel active un alignement de développement. La précision
mot à mot n’est pas encore qualifiée. Le code distingue disponibilité de la
fonction et validation de sa précision ; conserver cette distinction.

### Première écoute

Ouvrir un EPUB français importé, puis **Écouter ici**. Un appui long propose
également un départ depuis un mot ou un paragraphe. L’écoute ordinaire utilise
une réserve courte et poursuit la génération ; la commande de préparation
préalable du chapitre est distincte. Revenir au lecteur depuis le player pour
vérifier le passage entendu. Les durées d’attente dépendent de l’appareil et le
suivi mot à mot reste expérimental.

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

Pour une erreur de stockage, vérifier d’abord l’espace disponible et conserver
un journal expurgé pour le diagnostic. Ne jamais résoudre un problème de lancement
en supprimant les données de
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
