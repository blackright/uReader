# Registre des décisions d’architecture — uReader

Date de création : 10 novembre 2026

Les ADR expliquent le contexte, le choix, les alternatives et les conséquences des décisions structurantes. Ils complètent le [PRD](../PRD.md), l’[architecture](../Architecture.md), le [modèle de données](../Base-de-donnees.md) et les [contrats API](../API.md).

## Statuts et gouvernance

- **Proposé** : choix documenté pour revue, sans validation implicite du périmètre produit ni preuve technique.
- **Accepté** : choix explicitement demandé ou validé ; ce statut ne signifie pas implémenté ou testé.
- **Rejeté** : proposition examinée et non retenue, avec motif conservé.
- **Remplacé** : décision historique conservée et reliée à son successeur.

Les deux ADR mentionnant un choix accepté limitent explicitement cette acceptation à Flutter ou Pocket TTS, demandés dans les échanges initiaux. Le reste demeure proposé. Aucun prototype n’est présenté comme exécuté.

Pour accepter une proposition, consigner ici et dans l’ADR la date, le responsable de validation et les preuves requises. Toute modification substantielle d’une décision acceptée produit un nouvel ADR : conserver le précédent, indiquer le lien « remplacé par » et synchroniser les documents affectés. Une correction rédactionnelle peut être effectuée sur place sans changer le sens.

## Décisions

| ADR | Sujet | Statut initial |
|---|---|---|
| [ADR-0001](0001-flutter.md) | Utiliser Flutter pour l’application | Accepté — choix demandé par le porteur du projet |
| [ADR-0002](0002-modules-et-contrats.md) | Séparer fonctionnalités, domaine et adaptateurs | Proposé |
| [ADR-0003](0003-fonctionnement-local.md) | Privilégier une application locale sans serveur métier | Proposé — conditionné par DEC-02 et DEC-06 |
| [ADR-0004](0004-sqlite-et-fichiers.md) | Séparer données structurées SQLite et fichiers privés | Proposé — Drift candidat à confirmer |
| [ADR-0005](0005-contenu-et-reperes.md) | Partager un contenu canonique et des repères stables | Proposé — prototype de rendu nécessaire |
| [ADR-0006](0006-operations-reprenables.md) | Journaliser les opérations entre fichiers et base | Proposé |
| [ADR-0007](0007-pocket-tts.md) | Isoler Pocket TTS et conditionner son runtime mobile à un prototype | Accepté pour le choix Pocket TTS ; intégration proposée et à valider |
| [ADR-0008](0008-coordination-audio.md) | Confier toute l’écoute à un coordinateur unique | Proposé — adaptateurs audio à prototyper |
| [ADR-0009](0009-contenus-non-fiables.md) | Traiter les livres importés comme des entrées non fiables | Proposé — concrétisation de SEC-01 à SEC-06 |
| [ADR-0010](0010-modeles-et-confidentialite.md) | Vérifier les modèles et limiter les données conservées | Proposé — politique de distribution à préciser |

## Choix encore ouverts

Le porteur du projet a confirmé Android comme première plateforme et le français comme langue prioritaire de synthèse le 2026-11-10 (DEC-01 et DEC-03 du PRD). Restent ouverts les appareils et versions minimum, les voix françaises et leur faisabilité, le mode de navigation visuelle, le modèle économique et la synchronisation : voir le registre des décisions du PRD. Le runtime mobile Pocket TTS, le moteur EPUB, les versions des dépendances, l’outil de gestion d’état et les seuils de ressources doivent être précisés après les validations décrites.

FTS5, WAL, Drift et les bibliothèques audio restent des candidats ou options conditionnées par les essais. Aucun choix de backend, API REST ou fournisseur cloud n’est ajouté à ce stade.

## Ordre de validation conseillé

1. Définir les appareils Android de référence et les voix françaises à évaluer ; plateforme et langue prioritaires confirmées dans le PRD.
2. Prouver le runtime Pocket TTS et le rendu avec repères/accessibilité (ADR-0007 et ADR-0005/0009).
3. Valider le fond audio et les seuils de ressources (ADR-0008).
4. Confirmer stockage, reprise et distribution sécurisée (ADR-0004/0006/0010).
5. Consigner les décisions acceptées, leurs preuves et les mises à jour documentaires.

