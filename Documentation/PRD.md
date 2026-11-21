# PRD — uReader

Version : 0.2
Date : 10 novembre 2026  
Statut : proposition produit à valider  
Document source : [Cahier des charges](Cahier-des-charges.md)

## 1. Rôle du document

Ce Product Requirements Document décrit ce que fait uReader, les comportements attendus, ses règles métier et ses exigences de sécurité. Il précise le cahier des charges sans remplacer les décisions encore ouvertes. Il servira de référence à la constitution, aux spécifications des fonctionnalités et à la recette.

Les exigences ci-dessous définissent le comportement proposé pour la première version. Flutter et Pocket TTS sont demandés ; les autres choix de périmètre restent soumis aux décisions de la section 13. Les numéros de sections techniques ne prescrivent aucune bibliothèque ni architecture détaillée.

## 2. Vision et valeur produit

uReader permet de lire ses propres livres numériques et de les écouter avec Pocket TTS, en retrouvant facilement le passage courant. L’utilisateur garde le contrôle sur ses fichiers, ses préférences et ses données.

| Utilisateur | Besoin | Résultat attendu |
|---|---|---|
| Lecteur de livres personnels | Importer et retrouver ses ouvrages | Une bibliothèque consultable hors ligne |
| Lecteur alternant texte et audio | Continuer son livre pendant une autre activité | Une position cohérente entre lecture et écoute |
| Lecteur ayant des besoins d’accessibilité | Adapter le texte et utiliser les aides du système | Des parcours accessibles, y compris hors du lecteur |

La réussite se mesure d’abord par la fiabilité de ces parcours. L’application ne doit pas imposer un compte pour lire des fichiers locaux dans le périmètre proposé.

## 3. Périmètre et priorités

**P0** désigne une exigence nécessaire à la livraison du périmètre retenu. **P1** désigne une amélioration reportable. Une exigence conditionnée par une décision ouverte ne devient obligatoire qu’après validation de cette décision.

| Domaine | Première version proposée — P0 | Évolutions — P1 |
|---|---|---|
| Bibliothèque | Import EPUB sans DRM/TXT, métadonnées, recherche, tri, suppression | Collections, étiquettes, OPDS, Calibre |
| Lecture | Navigation, personnalisation, recherche, signets, reprise | Annotations, traduction, dictionnaires, lecture parallèle |
| Écoute | Pocket TTS, commandes, navigation par segment, vitesse, minuterie, arrière-plan | Voix supplémentaires et surlignage fin selon faisabilité |
| Données | Stockage local, gestion des modèles et caches | Synchronisation entre appareils, export de sauvegarde |
| Formats | EPUB sans DRM et TXT | PDF ; OCR à étudier séparément |

La boutique de livres, le contournement des DRM, le clonage de voix, les fonctions sociales et la génération de contenu ne font pas partie du périmètre proposé.

## 4. Parcours et écrans

### 4.1 Première utilisation

L’utilisateur arrive dans une bibliothèque vide proposant l’import. La préparation de Pocket TTS intervient lorsqu’il choisit l’écoute ; elle ne bloque pas la lecture visuelle. Tout téléchargement présente son utilité, sa taille connue et les conséquences d’une annulation.

### 4.2 Bibliothèque

L’écran présente les ouvrages et leur progression, un accès aux livres récents, la recherche, le tri et l’import. Un livre sans couverture ou auteur reste identifiable. Un import en cours et un échec sont distingués d’un livre prêt à ouvrir.

### 4.3 Lecteur

Le lecteur présente le contenu, l’accès aux chapitres, la progression, les signets, la recherche et les réglages visuels. La commande d’écoute agit sur le passage courant ; une action explicite sur un paragraphe permet de choisir un autre point de départ.

### 4.4 Commandes d’écoute

Les commandes indiquent le livre actif, l’état audio, lecture/pause, segment précédent/suivant, vitesse et minuterie. L’utilisateur peut revenir au passage actuellement lu. Les commandes système correspondent à la même session que celles de l’application.

Évolution demandée le 13 novembre 2026 : proposer un lecteur complet de type musical
(couverture, titre, chapitre, commande centrale et progression), ainsi qu'un mini-lecteur
pendant la navigation. Conserver les commandes actuelles dans un mode simplifié au
choix de l'utilisateur. Mémoriser ce choix ; changer de présentation conserve la même
session et la même position, sans interrompre ou relancer implicitement l'écoute.
Le lecteur complet est la présentation par défaut proposée pour la version produit.
Une durée totale inconnue avec le TTS n'est pas affichée comme une valeur mesurée.
Le périmètre décrit ici distingue les exigences produit de leur état de validation.
Le README présente les fonctionnalités disponibles et leurs limites actuelles.

### 4.5 Réglages et stockage

Les réglages regroupent les préférences visuelles et audio, l’état des modèles, leur espace occupé et la suppression des caches. Les erreurs proposent une action utile : réessayer, libérer de l’espace, choisir un fichier pris en charge ou poursuivre en lecture visuelle.

## 5. Exigences fonctionnelles et critères d’acceptation

| ID | Exigence P0 | Critère d’acceptation | Traçabilité cahier des charges |
|---|---|---|---|
| F-01 | Importer un EPUB sans DRM ou TXT via le sélecteur système | Un fichier valide produit une entrée ouvrable ; annuler ne crée aucune entrée inutilisable | BIB-01, BIB-06 |
| F-02 | Présenter et retrouver les livres | Titre/auteur disponibles, couverture de remplacement, recherche titre/auteur et tris fonctionnent hors ligne | BIB-02 à BIB-04 |
| F-03 | Supprimer un livre | La confirmation annonce les données retirées ; les autres livres et le fichier source restent intacts | BIB-05, REG-04 |
| F-04 | Lire et naviguer | Le contenu pris en charge est lisible ; les entrées de table des matières disponibles ouvrent le passage attendu | LEC-01, LEC-08 |
| F-05 | Personnaliser l’affichage | Police, taille, interligne, marges et thèmes persistent sans perdre le passage courant | LEC-02, LEC-03, REG-01 |
| F-06 | Sauvegarder la progression | Après changement de mise en forme et réouverture, le même passage logique est retrouvé | LEC-04, LEC-07 |
| F-07 | Gérer des signets | Un signet survit au redémarrage et ouvre le passage auquel il a été associé | LEC-05 |
| F-08 | Rechercher dans le livre | Les résultats ouvrent leurs passages ; une recherche vide ou sans résultat ne provoque pas d’erreur | LEC-06 |
| F-09 | Préparer et lancer Pocket TTS | L’état des modèles est visible ; une fois prêt, le moteur lit le segment choisi dans une langue validée | TTS-01, TTS-09, TTS-11 |
| F-10 | Contrôler l’écoute | Lecture, pause, arrêt et segments précédent/suivant agissent sans superposer des sessions | TTS-02, TTS-03 |
| F-11 | Régler la vitesse et la minuterie | La vitesse reste dans la plage validée ; l’expiration met en pause sans perdre la position | TTS-04, TTS-05 |
| F-12 | Écouter en arrière-plan | Sur la plateforme cible, écran verrouillé et commandes système pilotent la session active | TTS-06, TTS-07 |
| F-13 | Gérer les interruptions | Perte de sortie audio ou interruption met en pause ; aucune reprise automatique inattendue | TTS-08 |
| F-14 | Alterner texte et audio | Le retour au texte affiche le segment entendu ; reprendre l’écoute utilise le repère audio sauvegardé | TTS-10 |
| F-15 | Gérer les données locales | Préférences, modèles et caches sont distingués ; vider le cache conserve livres, positions et signets | REG-01 à REG-03 |

## 6. Règles métier

### 6.1 Import et bibliothèque

- **RM-01 — Copie locale :** l’import crée une copie dans l’espace privé de l’application. Le fichier original n’est ni modifié ni supprimé. Cette règle proposée concrétise REG-04.
- **RM-02 — Import transactionnel :** un ouvrage n’est déclaré prêt qu’après validation minimale et enregistrement réussi. Un échec ou une annulation nettoie les données temporaires.
- **RM-03 — Doublons :** deux fichiers strictement identiques ne créent pas automatiquement deux livres. L’application propose d’ouvrir l’exemplaire existant. Une édition différente est un ouvrage distinct ; aucun rapprochement automatique des positions n’est promis.
- **RM-04 — Métadonnées absentes :** utiliser le nom du fichier comme titre de remplacement et indiquer un auteur inconnu. L’absence de couverture ne bloque pas l’import.
- **RM-05 — Protection ou format invalide :** refuser proprement les fichiers non pris en charge et expliquer la limite, sans tentative de contournement de protection.
- **RM-06 — Suppression :** retirer la copie importée, ses métadonnées, positions, signets et caches audio associés après confirmation. Si le livre est lu à voix haute, arrêter sa session avant suppression. Les modèles partagés restent installés.

### 6.2 Position et navigation

- **RM-07 — Repères stables :** rattacher les positions au contenu et à l’identité du livre, jamais uniquement à un numéro de page affichée.
- **RM-08 — Positions distinctes :** conserver la position visuelle et le dernier segment audio. Une recherche ou une consultation d’un autre passage pendant l’écoute ne déplace pas silencieusement l’audio.
- **RM-09 — Passage explicite :** « écouter ici » déplace la position audio ; « afficher le passage lu » déplace la position visuelle. À la prochaine ouverture, reprendre le dernier mode utilisé et son repère, sans démarrer automatiquement le son.
- **RM-10 — Persistance :** sauvegarder aux changements de segment audio, aux navigations validées, à la pause et lors du passage en arrière-plan. Une fermeture brutale restaure le dernier repère durable ; la reprise audio peut relire le début du segment courant.
- **RM-11 — Fin de livre :** terminer l’audio, conserver le repère final et afficher la fin du livre. Ne pas démarrer automatiquement un autre ouvrage. La progression représente une position dans le contenu, pas une preuve de lecture intégrale.

### 6.3 Audio et modèles

- **RM-12 — Session unique :** une seule session audio est active. Lancer un autre livre sauvegarde puis arrête la session précédente.
- **RM-13 — Pause et arrêt :** la pause conserve la session prête à reprendre ; l’arrêt termine la session et libère les ressources de lecture sans effacer le repère sauvegardé.
- **RM-14 — Interruptions :** une déconnexion d’écouteurs, une perte audio nécessitant l’arrêt ou un appel met en pause. La première version propose une reprise manuelle. Aucune commande différée ne doit redémarrer une session arrêtée.
- **RM-15 — Minuterie :** à expiration, mettre en pause même si un segment n’est pas terminé. L’annulation ou la modification d’une minuterie remplace la précédente. Sa durée continue de s’écouler pendant une pause ; après redémarrage de l’application, elle n’est pas réactivée automatiquement.
- **RM-16 — Préparation :** aucun téléchargement de modèle ne débute sans action explicite. Annuler un téléchargement conserve les modèles déjà utilisables. Un modèle incomplet ne peut pas être sélectionné.
- **RM-17 — Langue indisponible :** indiquer l’absence de voix compatible et laisser l’accès à la lecture visuelle. Aucun basculement silencieux vers une synthèse distante ou une autre langue.
- **RM-18 — Cache :** les données audio sont régénérables et soumises à une limite à fixer après prototype. Leur éviction préserve le segment nécessaire à la lecture active. Supprimer un modèle utilisé exige d’arrêter explicitement l’écoute.
- **RM-19 — Texte prononcé :** exclure les scripts, styles et éléments masqués ; respecter l’ordre de lecture pris en charge. Les liens ne sont pas suivis pour produire de l’audio. Le traitement des notes et contenus complexes sera défini dans le corpus EPUB.

## 7. États et erreurs

| Domaine | États visibles | Comportement en cas d’échec |
|---|---|---|
| Import | Sélection, validation, import, prêt, échec | Nettoyer le temporaire ; préserver la bibliothèque |
| Modèle | Absent, téléchargement, vérification, prêt, erreur | Proposer une nouvelle tentative ; ne pas activer un fichier incomplet |
| Audio | Arrêté, préparation, lecture, pause, terminé, erreur | Arrêter le son, conserver le dernier repère durable et proposer une reprise explicite |
| Stockage | Disponible, insuffisant, erreur d’écriture | Ne pas annoncer une sauvegarde réussie ; proposer de libérer de l’espace |

Une commande lancée après changement de livre ne doit jamais appliquer le résultat de l’ancienne préparation au nouveau livre. Une annulation doit invalider les traitements encore en cours. Les messages utilisateurs ne doivent pas exposer de traces techniques ni de chemins internes.

## 8. Sécurité et confidentialité

Ces exigences constituent la politique produit proposée ; elles ne sont pas une certification de sécurité. Les livres importés, leurs archives, métadonnées, images et liens sont considérés comme des entrées non fiables.

| ID | Exigence P0 | Validation attendue |
|---|---|---|
| SEC-01 | Ne pas exécuter le JavaScript ni les contenus actifs d’un EPUB ; interdire les ponts vers des fonctions privilégiées | Un EPUB de test ne peut déclencher ni code privilégié ni action système |
| SEC-02 | Empêcher les accès hors du répertoire d’import, les traversées de chemins et les liens d’archive dangereux | Une archive hostile ne peut écrire ni lire hors de son espace autorisé |
| SEC-03 | Borner taille de fichier, taille décompressée, nombre d’entrées et ressources de traitement | Les fichiers dépassant les limites sont refusés proprement ; les seuils doivent être fixés avant livraison |
| SEC-04 | Désactiver les entités XML externes et les chargements réseau automatiques ; aucun média distant ni pixel de suivi chargé à l’ouverture | Ouvrir un livre ne provoque aucune requête externe provenant de son contenu |
| SEC-05 | Ouvrir un lien externe uniquement après action explicite ; limiter aux schémas autorisés, définis dans la spécification | Les liens dangereux ou inconnus sont refusés ; aucun lien ne s’ouvre seul |
| SEC-06 | Conserver livres et données dans l’espace privé de l’application avec permissions minimales | L’import utilise le sélecteur système sans accès global injustifié aux fichiers |
| SEC-07 | Ne transmettre aucun livre, extrait ou audio à un service distant dans le périmètre local | Les essais réseau confirment l’absence de transmission de contenu |
| SEC-08 | Télécharger les modèles via une connexion chiffrée depuis des sources autorisées ; vérifier intégrité et provenance avant activation | Un fichier altéré ou de provenance non validée est refusé ; une empreinte provenant du même canal ne suffit pas à établir seule la provenance |
| SEC-09 | Exclure le contenu des livres, les noms de fichiers et les chemins personnels des journaux ; pas de télémétrie distante par défaut | Inspection des journaux et du trafic sur les parcours de recette |
| SEC-10 | Supprimer les données applicatives annoncées ; exclure par défaut les livres, caches et données de lecture des sauvegardes système automatiques | Vérification de la configuration et des scénarios de suppression ; les limites liées aux copies externes sont expliquées |
| SEC-11 | Examiner les dépendances et corriger les vulnérabilités exploitables sur les parcours livrés | Revue documentée avant publication, notamment pour les parseurs et le rendu |
| SEC-12 | Ne placer aucun secret dans le dépôt ou les journaux ; protéger les clés de signature de distribution | Contrôle des artefacts et de la procédure de livraison |

Le chiffrement additionnel des livres au niveau applicatif et un verrou biométrique ne sont pas inclus à ce stade. Le produit s’appuie sur l’isolation du système et ne promet pas de protéger les données sur un appareil compromis. La suppression locale ne garantit pas l’effacement physique du support ni celui de copies créées hors de l’application.

## 9. Données et conservation

| Donnée | Usage | Conservation et suppression |
|---|---|---|
| Copie du livre et couverture | Lecture et bibliothèque | Jusqu’à suppression du livre |
| Métadonnées et identité du contenu | Identification, tri, détection de doublons | Supprimées avec le livre |
| Repères visuels/audio, signets | Reprise et navigation | Supprimés avec le livre |
| Préférences | Personnalisation | Jusqu’à réinitialisation des réglages ou effacement des données applicatives |
| Modèles et voix | Synthèse | Jusqu’à suppression explicite ou remplacement validé |
| Cache audio et fichiers temporaires | Réduire l’attente | Éviction contrôlée, nettoyage après échec, suppression sur demande |
| Diagnostics locaux sans contenu | Comprendre les erreurs | Durée et volume bornés à définir avant livraison |

Aucun compte, mot de passe ou profil serveur n’est nécessaire dans le périmètre proposé. Une future synchronisation exigera un complément au PRD sur l’authentification, les droits d’accès, le consentement, les conflits et la suppression distante.

## 10. Accessibilité, qualité et performances

- **QUAL-01 :** tous les parcours P0 sont utilisables avec le lecteur d’écran de la plateforme cible, avec libellés, états et ordre de focus cohérents.
- **QUAL-02 :** les commandes restent accessibles à la taille maximale de texte système retenue pour la recette ; les thèmes ne transmettent aucune information essentielle uniquement par couleur.
- **QUAL-03 :** import, recherche et synthèse ne bloquent pas les commandes de navigation ou d’annulation.
- **QUAL-04 :** un échec d’import ou de TTS ne compromet ni les autres livres ni les données déjà enregistrées.
- **QUAL-05 :** les migrations de stockage conservent les données ou échouent sans les détruire ; aucun effacement automatique pour résoudre une erreur de migration.
- **QUAL-06 :** après installation des modèles compatibles, les parcours locaux sont testés en mode avion.

Les seuils ci-dessous sont des conditions de préparation de la recette, sans valeurs inventées avant mesure :

| Indicateur à fixer | Méthode | Moment de décision |
|---|---|---|
| Temps d’ouverture et d’import | Corpus de tailles variées sur appareils cibles | Après prototype du lecteur |
| Attente avant le premier son et coupures entre segments | Mesures Pocket TTS, démarrage à froid et à chaud | Après prototype TTS |
| Mémoire et stabilité sur écoute prolongée | Session longue avec arrière-plan et navigation | Avant validation de l’architecture |
| Batterie, stockage, taille des modèles et plafond de cache | Mesures sur appareils représentatifs | Avant engagement du périmètre de livraison |
| Limites d’archives et durée des diagnostics | Essais de fichiers volumineux et malformés | Avant recette de sécurité |

Les valeurs retenues seront consignées dans le plan de validation avec appareils, corpus et versions. Les mesures restent locales sauf consentement explicite à un partage de diagnostic.

## 11. Validation et conditions de livraison

La recette reprend REC-01 à REC-12 du cahier des charges et vérifie chaque F-xx, RM-xx, SEC-xx et QUAL-xx applicable au périmètre validé.

Scénarios complémentaires indispensables :

1. Import interrompu, doublon, espace insuffisant et archive malveillante : aucune corruption ni accès hors du périmètre autorisé.
2. Téléchargement interrompu ou modèle altéré : modèle inutilisable clairement identifié, lecture visuelle disponible.
3. Changement de livre pendant la préparation TTS : aucun son ni position provenant de l’ancien livre dans la nouvelle session.
4. Recherche visuelle pendant l’écoute : position audio inchangée ; retour au passage entendu possible.
5. Appel, retrait des écouteurs, minuterie et fermeture brutale : aucune reprise sonore automatique ; repère durable récupérable.
6. Suppression du cache puis du livre : préférences et autres ouvrages conservés ; fichier source intact.
7. Livre comportant scripts et ressources externes : absence d’exécution et de requêtes automatiques.

La livraison nécessite :

- Des décisions de périmètre explicites et des seuils de validation renseignés.
- Une faisabilité Pocket TTS démontrée sur les appareils retenus, y compris langues prioritaires et arrière-plan.
- Les critères P0 applicables satisfaits, sans anomalie bloquante de sécurité, perte de données ou lecture audio.
- Une revue des licences des dépendances et des modèles, ainsi qu’une documentation des limites connues.
- Un rapport de recette reliant les exigences aux preuves de validation.

## 12. Dépendances et risques produit

| Risque | Impact | Réponse attendue |
|---|---|---|
| Pocket TTS incompatible ou trop coûteux sur appareil cible | Écoute locale non livrable comme prévue | Prototype précoce ; réviser explicitement appareils ou périmètre |
| Langue ou voix prioritaire indisponible | Valeur produit insuffisante | Vérifier avant de promettre une couverture linguistique |
| EPUB complexes ou malformés | Lecture incorrecte, import dangereux | Corpus représentatif et hostile ; limites documentées |
| Repères texte/audio instables | Reprise au mauvais passage | Valider segmentation et ancrages avant développement complet |
| Restrictions du système en arrière-plan | Écoute interrompue | Essais sur appareils réels et versions retenues |
| Licences ou redistribution des modèles incompatibles | Distribution impossible | Revue avant intégration définitive |

## 13. Registre des décisions

| ID | Décision | Proposition actuelle | Échéance |
|---|---|---|---|
| DEC-01 | Plateformes et appareils minimum | Android en premier : validé par le porteur le 2026-11-10 ; appareils et versions minimum encore ouverts | Appareils à définir avant prototype ciblé |
| DEC-02 | TTS entièrement sur appareil obligatoire ? | Oui, sous réserve de faisabilité | Avant engagement d’architecture |
| DEC-03 | Langues et voix prioritaires | Français prioritaire pour la synthèse : validé par le porteur le 2026-11-10 ; voix et faisabilité encore à vérifier | Voix à sélectionner et valider dans le prototype TTS |
| DEC-04 | Formats initiaux | EPUB sans DRM et TXT ; PDF ultérieur | Avant spécification de l’import |
| DEC-05 | Navigation visuelle | Défilement, pagination ou les deux | Avant maquettes du lecteur |
| DEC-06 | Compte et synchronisation | Pas de compte ; cloud reporté | Avant validation du périmètre |
| DEC-07 | Langues de l’interface et distribution | À définir | Avant préparation de publication |
| DEC-08 | Performances et limites de ressources | Valeurs issues des prototypes | Avant recette |
| DEC-09 | Modèle économique | À définir | Avant publication |

Une décision validée doit mettre à jour ce PRD et le cahier des charges pour éviter deux versions contradictoires. Les règles détaillées ajoutées ici sont des propositions produit et doivent être incluses dans la revue du document.

## 14. Historique

| Version | Date | Évolution |
|---|---|---|
| 0.2 | 10 novembre 2026 | Confirmation Android et français pour la synthèse ; DEC-01 et DEC-03 partiellement résolues, sans preuve technique implicite |
| 0.1 | 10 novembre 2026 | Première rédaction : périmètre, parcours, règles métier, sécurité, données et acceptation |
