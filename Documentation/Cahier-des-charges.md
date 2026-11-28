# Cahier des charges — uReader

Actualisation du 26 novembre 2026 : le prototype de narration française évolue
vers Kokoro SIWIS lexical minimal, choisi explicitement par le porteur. Le traitement
reste local ; Pocket demeure un profil historique explicite. Cette décision ne
vaut pas qualification de publication ou d'endurance. Voir DEC-10 du [PRD](PRD.md)
et [ADR-0011](ADR/0011-kokoro-siwis.md).

Version : 0.2
Date : 10 novembre 2026  
Statut : première version de travail

## 1. Présentation du projet

uReader est une application de lecture de livres numériques développée avec Flutter et intégrant Pocket TTS pour la lecture à voix haute. Elle doit permettre de passer simplement de la lecture visuelle à l’écoute, en conservant sa position dans le livre.

Ce document définit les besoins fonctionnels, les contraintes et les critères de recette du projet. Il servira de base à la constitution du projet puis aux spécifications détaillées. Les hypothèses et décisions ouvertes sont signalées explicitement ; elles ne constituent pas des engagements validés.

## 2. Objectifs et utilisateurs

L’application s’adresse aux lecteurs souhaitant lire leurs propres livres numériques, poursuivre leur lecture en audio et adapter l’affichage à leurs besoins. Elle doit également prendre en compte les personnes utilisant de grands caractères ou des technologies d’assistance.

Objectifs principaux :

- Regrouper les livres personnels dans une bibliothèque simple à utiliser.
- Offrir une lecture confortable et personnalisable.
- Faire de l’écoute une fonction centrale grâce à Pocket TTS.
- Conserver une position de lecture cohérente entre affichage et audio.
- Favoriser le fonctionnement local et la confidentialité.

## 3. Orientations et décisions

| Sujet | Orientation | Statut |
|---|---|---|
| Framework de l’application | Flutter | Demandé |
| Moteur de synthèse vocale | Pocket TTS | Demandé ; intégration à valider techniquement |
| Plateforme de lancement | Android en premier | Validé par le porteur du projet le 2026-11-10 ; appareils et versions minimum à définir |
| Langue prioritaire de synthèse | Français | Validé par le porteur du projet le 2026-11-10 ; voix et faisabilité à vérifier |
| Autres plateformes | iOS et ordinateurs à étudier ultérieurement | À décider |
| Formats de la première version | EPUB sans DRM et TXT | Proposition de périmètre |
| Exécution de la synthèse vocale | Sur l’appareil | Hypothèse à confirmer et à valider techniquement |
| Synchronisation cloud | Reportée après la première version | Proposition |
| Compte utilisateur | Non nécessaire pour les fonctions locales | Proposition |

## 4. Périmètre fonctionnel proposé pour la première version

### 4.1 Bibliothèque

- **BIB-01** : importer un fichier EPUB sans DRM ou TXT depuis le sélecteur de fichiers du système.
- **BIB-02** : afficher le titre, l’auteur et la couverture lorsqu’ils sont disponibles, avec des valeurs de remplacement sinon.
- **BIB-03** : rechercher un livre par titre ou auteur et trier la bibliothèque par titre ou dernière ouverture.
- **BIB-04** : afficher les livres récemment ouverts et leur progression.
- **BIB-05** : retirer un livre de la bibliothèque après confirmation, en indiquant clairement quelles données locales seront supprimées.
- **BIB-06** : signaler les fichiers invalides, protégés ou non pris en charge sans interrompre le fonctionnement de l’application.

### 4.2 Lecture visuelle

- **LEC-01** : ouvrir un livre et naviguer dans son contenu ; exploiter la table des matières lorsqu’elle existe.
- **LEC-02** : régler la taille du texte, la police, l’interligne et les marges.
- **LEC-03** : proposer des thèmes clair, sombre et sépia.
- **LEC-04** : enregistrer automatiquement la position et la restaurer lors de la prochaine ouverture.
- **LEC-05** : ajouter, consulter et supprimer des signets.
- **LEC-06** : rechercher un texte dans le livre et accéder aux résultats.
- **LEC-07** : afficher la progression de lecture sans dépendre d’un numéro de page variable selon la mise en forme.
- **LEC-08** : proposer au minimum un mode de navigation cohérent ; le choix entre défilement, pagination ou les deux sera fixé lors de la conception.

### 4.3 Lecture à voix haute avec Pocket TTS

- **TTS-01** : lancer la lecture à voix haute depuis la position courante ou un paragraphe choisi.
- **TTS-02** : proposer les commandes lecture, pause et arrêt.
- **TTS-03** : permettre de revenir au segment précédent ou de passer au suivant ; viser une navigation par phrase lorsque la segmentation le permet.
- **TTS-04** : régler la vitesse de lecture dans une plage validée par les essais techniques.
- **TTS-05** : proposer une minuterie d’arrêt.
- **TTS-06** : poursuivre l’écoute en arrière-plan et écran verrouillé sur les plateformes retenues.
- **TTS-07** : exposer les commandes audio du système et prendre en charge les commandes des écouteurs compatibles.
- **TTS-08** : gérer les interruptions audio et la déconnexion des écouteurs sans reprise sonore inattendue.
- **TTS-09** : afficher les états de préparation, chargement, lecture et erreur, avec une possibilité de réessayer.
- **TTS-10** : conserver la position d’écoute et permettre de reprendre la lecture visuelle au passage correspondant.
- **TTS-11** : expliquer le téléchargement initial des modèles, leur taille et leur disponibilité avant de promettre une utilisation hors ligne.

La sélection des voix, les langues disponibles et le surlignage synchronisé dépendent des capacités effectivement vérifiées de Pocket TTS. Le surlignage mot à mot ne fait pas partie des engagements de cette première version.

### 4.4 Réglages et données

- **REG-01** : conserver les préférences d’affichage et d’écoute entre les sessions.
- **REG-02** : stocker localement les métadonnées de bibliothèque, positions et signets.
- **REG-03** : expliquer et permettre la suppression des modèles et caches audio téléchargés ou générés.
- **REG-04** : distinguer les fichiers importés des fichiers originaux afin de rendre les conséquences d’une suppression prévisibles.

## 5. Parcours principaux

1. **Importer et lire** : ouvrir la bibliothèque, importer un fichier, sélectionner le livre et commencer la lecture.
2. **Passer à l’écoute** : lancer Pocket TTS depuis le passage affiché, puis contrôler la lecture depuis l’application ou les commandes système.
3. **Revenir au texte** : arrêter ou mettre en pause l’écoute et retrouver le passage correspondant dans le lecteur.
4. **Reprendre plus tard** : rouvrir l’application et retrouver le livre et la dernière position enregistrée.
5. **Personnaliser** : modifier l’affichage et les réglages audio, puis retrouver ces préférences à la session suivante.

## 6. Exigences non fonctionnelles

### Confidentialité et fonctionnement local

- La lecture des fichiers déjà importés et la consultation de la bibliothèque doivent fonctionner sans connexion.
- L’écoute hors ligne constitue l’objectif proposé après installation des modèles ; sa faisabilité doit être démontrée sur les appareils cibles.
- Aucun livre ni extrait ne doit être envoyé à un service distant sans choix explicite de l’utilisateur.
- Les journaux techniques doivent éviter d’enregistrer le contenu des livres.
- Les accès aux fichiers et les permissions système doivent être limités aux besoins des fonctionnalités.

### Accessibilité et ergonomie

- Les commandes doivent disposer de libellés accessibles et d’un ordre de navigation cohérent.
- L’interface doit rester utilisable avec les réglages de grande taille de texte du système.
- Les thèmes doivent offrir un contraste lisible ; une information essentielle ne doit pas dépendre uniquement d’une couleur.
- Les commandes principales de lecture et d’écoute doivent rester facilement accessibles.

### Fiabilité et performances

- Un fichier invalide ou une erreur de synthèse ne doit pas fermer l’application ni rendre la bibliothèque inaccessible.
- Les opérations longues doivent afficher leur état et proposer une annulation lorsque cela est possible.
- Le traitement audio doit limiter les blocages de l’interface, la consommation mémoire et la croissance du cache.
- Les objectifs chiffrés de latence, mémoire, batterie et taille des modèles seront fixés après un prototype sur des appareils représentatifs.
- Les positions doivent utiliser des repères stables dans le contenu, indépendants de la taille de police et de l’orientation.

### Architecture et maintenance

- Séparer l’interface Flutter, l’import et l’analyse des livres, le stockage, le rendu du texte et la synthèse vocale.
- Isoler Pocket TTS derrière une interface afin de faciliter les essais et les évolutions.
- Documenter les dépendances, leurs licences et les contraintes de distribution des modèles.
- Prévoir une migration des données lorsque le schéma de stockage évolue.
- Tester en priorité l’import, la conservation des positions et le cycle de vie de la lecture audio.

## 7. Fonctions envisagées après la première version

- PDF, avec traitement distinct des documents textuels et des pages scannées.
- Surlignages, annotations et export des notes.
- Collections, étiquettes et statistiques de lecture.
- Dictionnaires, traduction et dictionnaire de prononciation.
- Catalogues OPDS et connexion à une bibliothèque Calibre.
- Synchronisation de la bibliothèque et des positions entre appareils.
- Lecture parallèle de deux ouvrages.
- Voix supplémentaires et surlignage synchronisé plus précis, selon faisabilité.

Ces fonctions restent des pistes, sans engagement de livraison. La gestion des DRM, une boutique de livres et l’OCR ne sont pas inclus dans le périmètre initial proposé.

## 8. Références fonctionnelles

Les applications suivantes servent de références pour comprendre les usages et concevoir notre propre expérience :

| Application | Axes à étudier | Source |
|---|---|---|
| Moon+ Reader | Personnalisation, gestes, navigation et commandes d’écoute | https://www.moondownload.com/ |
| Voice Dream Reader | Expérience centrée sur l’écoute et réglages audio | https://www.voicedream.com/ |
| Thorium Reader | Accessibilité et articulation lecture/écoute | https://www.thoriumreader.com/ |
| KOReader | Réglages avancés, navigation et outils de lecture | https://koreader.rocks/user_guide/ |
| Readest | Lecture parallèle, bibliothèque et intégrations | https://www.readest.com/docs |

Les fonctionnalités servent d’inspiration. Toute réutilisation de code ou de ressources devra respecter les licences applicables.

## 9. Validation technique préalable

Avant de figer l’architecture et les promesses de la première version, un prototype doit vérifier :

1. L’intégration de Pocket TTS avec Flutter sur la plateforme cible.
2. La licence et les modalités de distribution du moteur et des modèles.
3. Les langues et voix répondant aux besoins retenus.
4. Le temps de génération, la mémoire, le stockage et la consommation sur appareil réel.
5. L’enchaînement de segments audio sans coupures gênantes.
6. La correspondance entre segments de texte, audio et position sauvegardée.
7. Le fonctionnement en arrière-plan, les interruptions et les commandes système.

Si les résultats ne permettent pas de respecter les exigences, documenter les limites et faire réviser le périmètre avant l’implémentation complète.

## 10. Critères de recette de la première version

| Référence | Scénario | Résultat attendu |
|---|---|---|
| REC-01 | Importer un EPUB valide et un TXT valide | Les livres apparaissent et leur contenu est lisible |
| REC-02 | Importer un fichier invalide ou non pris en charge | Un message compréhensible apparaît et les autres livres restent accessibles |
| REC-03 | Modifier la police et l’orientation puis rouvrir le livre | Le passage enregistré est retrouvé malgré le changement de mise en forme |
| REC-04 | Créer un signet, fermer puis rouvrir l’application | Le signet est conservé et ouvre le passage attendu |
| REC-05 | Lancer l’écoute depuis un paragraphe choisi | Le passage choisi est lu et les commandes audio fonctionnent |
| REC-06 | Mettre en pause l’écoute puis revenir au texte | Le passage correspondant à la position audio est visible |
| REC-07 | Verrouiller l’écran pendant l’écoute | L’écoute continue et les commandes système restent disponibles |
| REC-08 | Débrancher les écouteurs ou recevoir une interruption audio | Le comportement est prévisible et aucune reprise sonore inattendue ne se produit |
| REC-09 | Relancer l’application après une fermeture | La dernière position sauvegardée et les préférences sont restaurées |
| REC-10 | Couper le réseau après préparation des fichiers et modèles | La lecture fonctionne ; l’écoute fonctionne si le mode local a été validé |
| REC-11 | Utiliser un lecteur d’écran et agrandir le texte système | Les commandes principales restent identifiables et utilisables |
| REC-12 | Supprimer un livre ou un cache | Les éléments annoncés sont supprimés sans perte des autres livres |

Le corpus de livres de recette et les appareils de référence seront définis dans le plan de validation. Les cas particuliers de mise en page EPUB devront y être explicités.

## 11. Livrables et étapes

1. Cahier des charges et registre des décisions.
2. Constitution du projet fondée sur les exigences retenues.
3. Prototype Flutter/Pocket TTS et rapport de faisabilité.
4. Spécifications détaillées, maquettes des parcours et plan d’implémentation.
5. Première version couvrant bibliothèque, lecture et écoute.
6. Rapport de recette et documentation d’installation et d’utilisation.

Aucun calendrier ni budget n’est arrêté dans cette version.

## 12. Décisions encore à prendre

- Identifier les appareils Android et versions système cibles ; Android est confirmé comme première plateforme.
- Confirmer si la synthèse intégralement locale est obligatoire.
- Sélectionner les voix françaises et démontrer leur prise en charge ; le français est confirmé comme langue prioritaire de synthèse.
- Valider EPUB/TXT comme formats initiaux et la priorité du PDF.
- Choisir le mode de lecture : défilement, pagination ou les deux.
- Confirmer le report de la synchronisation cloud.
- Définir les langues de l’interface, le mode de distribution et le modèle économique éventuel.
- Fixer les objectifs de performance après les essais techniques.

## 13. Gestion des évolutions

Chaque modification du périmètre doit être consignée dans ce document avec sa date et son impact. Les fonctionnalités proposées ne deviennent des engagements qu’après validation explicite de leur périmètre. Les contraintes techniques découvertes doivent être répercutées dans les critères de recette et le plan de livraison.

| Version | Date | Modification |
|---|---|---|
| 0.2 | 10 novembre 2026 | Confirmation par le porteur du projet : Android en premier et français pour la synthèse vocale |
| 0.1 | 10 novembre 2026 | Création à partir des échanges initiaux sur Flutter, Pocket TTS et les références de lecteurs numériques |
