# Contribuer à uReader

Merci de contribuer à un lecteur EPUB Android utilisable, accessible et respectueux
des données personnelles. Le projet est en développement actif ; une fonction
implémentée n’est pas automatiquement une fonction qualifiée pour la production.

## Choisir un travail

Consultez les [issues](https://github.com/blackright/uReader/issues).
Les labels `P0` à `P3` indiquent la priorité ; `proposal` désigne une évolution
à préciser. Les critères d’acceptation et dépendances figurent dans chaque issue.

Laissez un commentaire sur l’issue avant un travail important pour coordonner
le périmètre. Pour une nouvelle dépendance, un format, une migration, un service
distant ou une modification d’architecture, discutez d’abord la proposition.
Une correction documentaire simple peut être proposée directement en pull request.
Ne recréez pas une fonction déjà présente : recherchez ses composants et ses tests.

## Préparer son environnement

Suivez le [démarrage du README](README.md#démarrer-le-projet) et le
[guide de développement](Documentation/Developpement.md). La lecture visuelle
et les tests hôte ne nécessitent pas d’installer des poids vocaux sur un téléphone.
Les bancs réels de synthèse exigent le bundle compatible et un appareil préparé.

Pour contribuer depuis un fork, remplacez `VOTRE_COMPTE` puis :

```bash
git clone https://github.com/VOTRE_COMPTE/uReader.git
cd uReader
git remote add upstream https://github.com/blackright/uReader.git
git fetch upstream
git switch -c feat/description-courte upstream/main
flutter pub get
```

Choisissez un nom de branche court, par exemple `fix/reader-position` ou
`docs/voice-installation`. Gardez les changements liés à une seule intention.

## Conventions de code

- Suivez l’analyseur configuré dans `analysis_options.yaml` et le format Dart.
- Respectez les responsabilités : contrats dans `domain`, comportements dans
  `features`, stockage et intégrations dans `infrastructure`, assemblage dans `app`.
- Réutilisez les contrats et services existants. Préservez la session audio unique,
  les repères canoniques et la distinction entre position visuelle et audio.
- Gérez annulation, ressources et réponses asynchrones périmées. Les EPUB et les
  paquets vocaux sont des entrées non fiables : gardez leurs contrôles et limites.
- Préservez la langue française de l’interface actuelle, ses libellés accessibles,
  le focus, les grands textes et les thèmes existants.
- Préservez les livres, signets, positions et préférences. Une migration demande
  une stratégie de conservation et de récupération ; pas de suppression de base
  pour faire passer un test.
- Évitez les nettoyages et mises à niveau sans rapport avec la correction.

## Vérifier ses changements

Formatez les fichiers Dart que vous avez modifiés, puis exécutez les contrôles
adaptés. Depuis la racine :

```bash
flutter analyze
flutter test --concurrency=1
flutter build apk --debug --target-platform android-arm64
```

Pour une itération ciblée :

```bash
flutter test test/features/listening/buffered_playback_test.dart
```

Un changement documentaire seul demande surtout une vérification des liens,
commandes et affirmations ; il n’impose pas une campagne audio complète.
Un changement natif, audio, de migration ou d’import demande les tests d’intégration
correspondants en plus des contrôles hôte. Lire les prérequis du laboratoire avant
exécution ; ne pas lancer un essai destructif sur des données personnelles.

Ajoutez une régression lorsqu’elle protège un comportement réel ou un cas d’échec.
Distinguez test automatisé, compilation, essai sur appareil et validation humaine.
Si un contrôle n’a pas été effectué, dites-le et expliquez pourquoi. N’annoncez
pas un résultat TalkBack, une qualité audible ou une précision mot à mot à partir
d’un simple test simulé.

## Ouvrir une pull request

1. Vérifiez `git status` et le diff : seuls les changements nécessaires doivent
   être présents. Le `.gitignore` n’arrête pas un secret ajouté avec `--force`.
2. Committez sur votre branche avec un message décrivant le changement.
3. Poussez la branche vers votre fork : `git push -u origin feat/description-courte`.
4. Ouvrez une pull request vers `blackright/uReader`, branche **`main`**.
5. Indiquez l’issue liée, le comportement avant/après, les vérifications réellement
   exécutées et les limites restantes. Ajoutez des captures expurgées pour un
   changement visuel et les conséquences pour les données si nécessaire.

Utilisez `Closes #NUMERO` seulement si la pull request satisfait tous les critères
de l’issue. Une livraison partielle doit laisser les critères restants visibles.
Les propositions et validations reportées ne sont pas des fonctionnalités validées.

### Checklist avant revue

- [ ] Périmètre clair, lié à une issue ou expliqué dans la description.
- [ ] Architecture et comportement existants préservés ou changement documenté.
- [ ] Contrôles pertinents exécutés, résultats et contrôles non exécutés indiqués.
- [ ] Accessibilité, annulation et erreurs vérifiées si concernées.
- [ ] Aucun secret, livre privé, poids vocal, base, enregistrement ou artefact de build.
- [ ] Documentation et notices mises à jour si nécessaire.

## Rapporter un problème

Donnez les étapes minimales, le résultat attendu et observé, les versions Android,
Flutter et de l’application, puis indiquez si la voix est installée et si l’essai
est connecté ou hors ligne. Une petite ressource synthétique reproductible est
préférable à un livre personnel. Expurgez journaux et captures.

Pour un problème de sécurité sensible, ne publiez ni contenu privé ni exploit
avec secrets dans une issue publique. Demandez d’abord au mainteneur un canal
privé en décrivant uniquement la catégorie du problème.

## Licence et ressources tierces

Les contributions au code sont proposées sous la [licence MIT du projet](LICENSE).
N’ajoutez que du contenu que vous êtes autorisé à distribuer. Les bibliothèques,
modèles, polices et voix gardent leurs licences ; conservez leurs notices et
expliquez la provenance de toute nouvelle ressource.
