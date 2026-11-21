# ADR-0004 — Séparer données structurées SQLite et fichiers privés

Date : 10 novembre 2026  
Statut : Proposé — Drift candidat à confirmer  
Origine : échanges initiaux et architecture 0.1  
Validation : non encore enregistrée

## Contexte

La bibliothèque possède des relations, contraintes d’intégrité et repères durables ; les livres et modèles sont des objets volumineux.

## Décision

Stocker métadonnées, blocs canoniques, positions, signets et opérations dans SQLite. Utiliser des fichiers privés pour originaux, ressources, modèles et audio. Proposer Drift comme accès typé. Activer les clés étrangères, paramétrer les requêtes et versionner les migrations. FTS5 et WAL restent soumis à validation dans le runtime choisi.

## Alternatives considérées

Tout stocker en fichiers JSON : moins de dépendances mais intégrité et concurrence à reconstruire. Binaires en base : cohérence simplifiée mais gestion du volume différente. Base distante : incompatible avec l’autonomie locale proposée.

## Conséquences et compromis

Les contraintes relationnelles protègent les données. Fichiers et base ne sont pas atomiques ensemble ; ADR-0006 fournit la reprise. Le cache demeure reconstructible.

## Validation attendue

Tester doublons concurrents, clés composites inter-livres, cascades, Unicode et migrations ; vérifier FTS5 et politique de durabilité sur appareil.

## Conditions de réexamen

Une limite mesurée de requêtes, volume ou distribution impose de changer le stockage ou son adaptateur.

## Traçabilité

PRD : REG via F-15, QUAL-05 ; Base de données : sections 1 à 6.

Documents : [PRD](../PRD.md), [Architecture](../Architecture.md), [Base de données](../Base-de-donnees.md), [API](../API.md). Retour au [registre](README.md).

