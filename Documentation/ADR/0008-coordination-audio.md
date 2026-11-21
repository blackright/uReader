# ADR-0008 — Confier toute l’écoute à un coordinateur unique

Date : 10 novembre 2026  
Statut : Proposé — adaptateurs audio à prototyper  
Origine : échanges initiaux et architecture 0.1  
Validation : non encore enregistrée

## Contexte

UI, commandes système, préproduction et interruptions peuvent agir simultanément et produire des lectures ou écritures obsolètes.

## Décision

Un coordinateur possède la session et sérialise les commandes. Étiqueter les travaux par sessionId/generation et rejeter les retours obsolètes. Générer initialement des fichiers complets par segments, avec préproduction bornée et cache reconstructible. Persister le repère du segment réellement joué. Proposer audio_service et just_audio sans les considérer validés.

## Alternatives considérées

Lecteur indépendant par écran : risque de sessions superposées. Génération du livre entier : attente et stockage élevés. PCM streaming immédiat : latence potentiellement meilleure mais protocole et reprise plus complexes.

## Conséquences et compromis

Une seule source d’état dessert UI et système. Le découpage peut introduire une attente ou des coupures ; le prototype doit les mesurer. La pause sur interruption est suivie d’une reprise manuelle ; aucun son au redémarrage.

## Validation attendue

Tester verrouillage, appel, retrait écouteurs, arrêt pendant génération, seek, changement de livre, minuterie et arrêt forcé. Mesurer continuité et consommation.

## Conditions de réexamen

Les fichiers par segments ne satisfont pas les seuils mesurés ; envisager le streaming dans un ADR dédié, en conservant la session unique.

## Traçabilité

PRD : F-10 à F-14, RM-12 à RM-15 ; Architecture : section 6.

Documents : [PRD](../PRD.md), [Architecture](../Architecture.md), [Base de données](../Base-de-donnees.md), [API](../API.md). Retour au [registre](README.md).

