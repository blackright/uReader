# uReader

**Vos livres, votre rythme. Lire et écouter ses EPUB sur Android.**

uReader est un lecteur EPUB développé avec Flutter, avec une bibliothèque locale,
un lecteur personnalisable et une narration française embarquée avec Pocket TTS.
Les livres restent sur l’appareil ; la lecture ne dépend pas d’un compte ni d’un
service de synthèse distant.

> **En développement actif.** L’application est un prototype fonctionnel Android.
> La fluidité audio, la synchronisation mot à mot et certaines recettes
> d’accessibilité sont encore en cours de validation. Aucune version de production
> n’est annoncée à ce stade.

## Une bibliothèque à emporter

- **Importer ses EPUB** depuis le sélecteur de fichiers Android, puis les retrouver
  dans une bibliothèque avec couvertures, recherche, tri et détection des doublons.
- **Lire à son rythme** en mode paginé ou défilant, avec navigation par chapitre,
  thèmes, réglages typographiques, progression et reprise de lecture.
- **Retrouver ses passages** avec les signets et les actions sur un mot ou un
  paragraphe pour commencer l’écoute à l’endroit choisi.
- **Écouter en français** avec une voix installée localement, un player complet,
  un mini-player et une présentation simplifiée.
- **Suivre la narration** avec le passage entendu et le suivi automatique.
  Le surlignage mot à mot reste expérimental.

Les positions de lecture visuelle et audio sont distinctes : consulter un autre
passage ne déplace pas automatiquement la narration.

## Hors ligne, par conception

Après import du livre et installation de la voix, la lecture et la synthèse
fonctionnent localement, avec ou sans connexion. Aucun serveur de narration n’est
actuellement intégré. Les poids vocaux sont installés explicitement et vérifiés
par empreinte avant utilisation.

Le profil pris en charge vise les EPUB 2/3 à mise en page adaptable, sans DRM.
Les EPUB protégés ou à mise en page fixe ne sont pas pris en charge. Les livres
dans d’autres langues restent consultables ; la voix livrée vise le français.

## Démarrer le projet

### 1. Préparer les outils

Installez Git, Flutter et Android Studio. Cette application vise actuellement
**Android ARM64**, à partir d’Android 8.0 / API 26. Un téléphone physique ARM64
est recommandé ; les émulateurs x86 ne correspondent pas à la cible compilée.

| Élément | À vérifier |
| --- | --- |
| Flutter / Dart | Flutter fournissant Dart **>= 3.13.4 et < 4.0.0**, selon `pubspec.yaml` ; configuration utilisée : Flutter 3.47.5 / Dart 3.13.4 |
| Android Studio | SDK Android, SDK Platform-Tools, Build-Tools et Command-line Tools installés via SDK Manager |
| Java / Gradle | Le wrapper et `android/gradle/gradle-daemon-jvm.properties` sont versionnés ; Gradle est configuré pour provisionner **Java 25** pour son daemon |
| Téléphone | Options développeur et débogage USB activés ; autorisation de débogage acceptée |

Le premier téléchargement des dépendances, outils SDK et de la JVM nécessite
une connexion. L’application fonctionne ensuite localement une fois les livres
et, pour l’écoute, la voix installés. Les essais matériels effectués notamment
sur Samsung SM-G965F / Android 10 ne qualifient pas tous les appareils.

### 2. Récupérer et lancer l’application

Dans un terminal :

```bash
git clone https://github.com/blackright/uReader.git
cd uReader
flutter --version
flutter doctor -v
flutter doctor --android-licenses
flutter pub get
flutter devices
```

Corrigez les points signalés pour la chaîne Android dans `flutter doctor`.
Branchez le téléphone, déverrouillez-le et acceptez l’autorisation USB. Remplacez
`IDENTIFIANT_ANDROID` ci-dessous par l’identifiant affiché par `flutter devices` :

```bash
flutter run -d IDENTIFIANT_ANDROID
```

Les contrôles d’autres plateformes dans `flutter doctor` ne sont pas des
prérequis pour ce projet Android. La première compilation peut être longue.
Les chemins SDK, caches et clés restent locaux ; ne copiez pas le fichier
`android/local.properties` d’une autre machine.

### 3. Lire son premier livre, sans modèle vocal

1. Placez un EPUB sans DRM à mise en page adaptable dans les fichiers du téléphone.
2. Dans uReader, ouvrez **Livres**, puis **Importer un EPUB**.
3. Sélectionnez le fichier avec le sélecteur Android et attendez la fin de l’import.
4. Ouvrez sa couverture dans la bibliothèque. Utilisez les pages ou le défilement,
   le sommaire et les réglages de lecture.
5. Fermez puis rouvrez le livre pour retrouver votre repère visuel.

Une copie privée est utilisée pour la lecture ; le fichier original est conservé.
La narration n’est pas nécessaire pour lire. Les PDF, EPUB protégés et EPUB à mise
en page fixe ne font pas partie du profil pris en charge.

### 4. Activer la narration française

**Le dépôt ne fournit pas actuellement de téléchargement public vérifié du bundle
vocal prêt à installer.** Le guide permet de lancer et tester la lecture visuelle,
mais ne permet pas encore à un nouvel utilisateur d’activer l’audio sans obtenir
ou reconstruire le paquet exact. Le suivi de cette limitation est dans
[l’issue #16](https://github.com/blackright/uReader/issues/16).

Si vous disposez déjà du bundle compatible :

1. Consultez le [catalogue vocal](assets/models/manifest.json). Les sept fichiers,
   leur taille et leur SHA-256 doivent correspondre exactement ; ne remplacez pas
   les graphes par d’autres modèles portant des noms semblables.
2. Copiez les sept fichiers dans un même sous-dossier du téléphone, par exemple
   `Téléchargements/uReader-voice-fr`. Ne sélectionnez pas le dossier Téléchargements
   lui-même si Android en interdit l’accès.
3. Ouvrez **Voix → Installer depuis un dossier**. Entrez dans ce sous-dossier,
   choisissez **Utiliser ce dossier**, puis autorisez l’accès.
4. Attendez la copie, la vérification et l’annonce de l’installation terminée.
5. Revenez dans un livre français. Utilisez **Écouter ici**, ou un appui long sur
   un mot/paragraphe et l’action de départ proposée. Le player permet pause et arrêt.

Le catalogue debug actuel vise `1.1.0-alignment-preview`. Le nom `manifest.json`
dans le paquet vocal désigne le manifeste d’exécution ; il ne faut pas y copier
le catalogue de l’application `assets/models/manifest.json`.
Le surlignage mot à mot reste expérimental. La commande distincte de préparation
préalable du chapitre peut imposer une attente plus longue que l’écoute ordinaire.

Le [guide de développement](Documentation/Developpement.md) détaille les fichiers,
la vérification et les prérequis des outils d’export.

### Dépannage rapide

| Problème | Que vérifier |
| --- | --- |
| `flutter` introuvable ou Dart trop ancien | Installation Flutter, `PATH` du terminal et résultat de `flutter --version` ; ne pas diminuer la contrainte SDK pour contourner l’erreur |
| Aucun appareil / appareil non autorisé | Câble de données, débogage USB, autorisation sur le téléphone, puis `flutter devices` |
| SDK ou licences Android manquants | SDK Manager, Command-line Tools et `flutter doctor --android-licenses` |
| Téléchargement Gradle, Java ou dépendances bloqué | Connexion/proxy, sortie complète de la compilation et configuration du wrapper ; le premier build n’est pas hors ligne |
| Import refusé | EPUB sans DRM à mise en page adaptable, fichier non tronqué ; conserver le message précis du refus |
| Voix absente ou bundle refusé | Bundle compatible complet, sept empreintes et bon sous-dossier ; la lecture visuelle reste possible |
| Erreur de stockage | Espace libre et journal expurgé ; ne pas désinstaller ni effacer les données pour contourner le problème |

Si le problème persiste, ouvrez une [issue](https://github.com/blackright/uReader/issues)
avec étapes, résultat attendu/réel, versions et journaux expurgés. Ne joignez pas
vos livres privés, clés ou chemins personnels.

## Développement et vérifications

```bash
flutter analyze
flutter test --concurrency=1
flutter build apk --debug --target-platform android-arm64
```

Les tests d’intégration Android sont dans `integration_test/` et les tests natifs
dans `android/app/src/androidTest/`. Certains utilisent des ressources de
laboratoire à préparer explicitement. Les commandes d’intégration et les limites
sont décrites dans le [guide de développement](Documentation/Developpement.md).

La dernière série ciblée sur la lecture continue compte **102 tests hôte réussis**.
Le banc natif a également mesuré 60 segments synthétiques sur appareil. L’essai
sonore de génération et lecture simultanées reste à exécuter : ces résultats ne
prouvent pas encore une écoute prolongée sans interruption sur tous les livres.

## Contribuer

Les contributions au code, aux tests, à l’accessibilité et à la documentation sont
bienvenues. Consultez les [issues ouvertes](https://github.com/blackright/uReader/issues)
et le [guide de contribution](CONTRIBUTING.md) avant de commencer.

En bref : choisissez une issue, proposez un périmètre clair, créez une branche
dans votre fork, effectuez les vérifications adaptées et ouvrez une pull request
vers `main`. Les issues portant `proposal` demandent une décision de périmètre
avant une implémentation importante.

## Organisation du code

```text
lib/
  domain/           Contrats et règles métier
  features/         Bibliothèque, lecteur, narration et players
  infrastructure/   EPUB, SQLite, fichiers privés et audio
  app/              Assemblage de l’application
android/            Hôte Android et moteur vocal natif ONNX
test/               Tests unitaires et de widgets
integration_test/   Parcours sur appareil
assets/             Démonstration, catalogue et mentions de licences
Documentation/      Architecture, exigences et décisions techniques
validation/         Sources des outils de reproduction et de mesure
```

## Documentation

- [Architecture](Documentation/Architecture.md)
- [API et contrats](Documentation/API.md)
- [Base de données](Documentation/Base-de-donnees.md)
- [Décisions d’architecture](Documentation/ADR/README.md)
- [Exigences produit](Documentation/PRD.md)
- [Développement et ressources](Documentation/Developpement.md)
- [Guide de contribution](CONTRIBUTING.md)

## Licence

Le code du projet est publié sous [licence MIT](LICENSE).
Les moteurs, modèles, voix et autres composants conservent leurs licences
respectives : voir les [mentions tierces](assets/models/THIRD_PARTY_NOTICES.txt)
et la [licence Pocket TTS](assets/models/POCKET_TTS_LICENSE.txt).
