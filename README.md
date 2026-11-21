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

### Prérequis

| Outil | Configuration |
| --- | --- |
| Flutter | Version compatible avec Dart **3.13.4 ou ultérieur**, selon `pubspec.yaml` |
| Android | SDK et outils de compilation installés avec Android Studio |
| Java | JDK compatible avec le wrapper Gradle du dépôt ; JDK d’Android Studio recommandé |
| Appareil | Android **8.0 / API 26 minimum**, architecture **ARM64** |

Les essais matériels effectués jusqu’ici concernent notamment un Samsung SM-G965F
sous Android 10. Ils ne constituent pas une validation de tous les appareils.

```bash
git clone https://github.com/blackright/uReader.git
cd uReader
flutter doctor
flutter pub get
flutter devices
flutter run -d <identifiant-android>
```

Le wrapper Gradle et `pubspec.lock` sont versionnés. Les chemins du SDK, clés de
signature et caches restent propres à chaque machine.

### Installer la voix

La lecture visuelle est disponible sans poids vocaux. Pour l’audio, ouvrir
**Voix → Installer depuis un dossier**, puis sélectionner un dossier contenant les
sept fichiers du bundle compatible avec le catalogue embarqué.

**Les poids ne sont pas inclus dans Git.** Un ensemble quelconque de modèles
Pocket TTS ne suffit pas : noms, versions, interfaces et empreintes doivent
correspondre au [catalogue vocal](assets/models/manifest.json). Le bundle debug
actuel contient une extension expérimentale d’alignement ; cette extension n’est
pas une qualification de production.

Voir le [guide de développement](Documentation/Developpement.md) pour les
ressources vocales, l’architecture et les outils de vérification.

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

## Licence

Le code du projet est publié sous [licence MIT](LICENSE).
Les moteurs, modèles, voix et autres composants conservent leurs licences
respectives : voir les [mentions tierces](assets/models/THIRD_PARTY_NOTICES.txt)
et la [licence Pocket TTS](assets/models/POCKET_TTS_LICENSE.txt).
