# ADR-0002 — Séparer fonctionnalités, domaine et adaptateurs

Date : 10 novembre 2026  
Statut : Proposé  
Origine : échanges initiaux et architecture 0.1  
Validation : non encore enregistrée

## Contexte

Lecture, import et audio doivent évoluer sans coupler les écrans aux moteurs techniques.

## Décision

Organiser le produit en modules bibliothèque, lecteur, écoute et réglages. Faire dépendre les cas d’utilisation de contrats de dépôts, ReaderEngine, SpeechEngine et AudioPlayer. Injecter les dépendances par constructeur ; différer le choix de bibliothèque de gestion d’état.

## Alternatives considérées

Appels directs depuis les widgets : démarrage rapide mais règles et concurrence dispersées. Microservices : déploiement et réseau sans besoin établi pour la version locale.

## Conséquences et compromis

Les moteurs sont remplaçables et testables par de faux adaptateurs. Les contrats ont un coût de maintenance ; créer des interfaces aux frontières utiles, sans abstraction systématique de chaque classe.

## Validation attendue

Vérifier qu’un parcours peut utiliser un faux moteur vocal et qu’aucun widget n’accède directement au SQL ou au runtime TTS.

## Conditions de réexamen

Les frontières empêchent une fonctionnalité réelle ou introduisent une complexité disproportionnée.

## Traçabilité

PRD : F-01 à F-15 ; Architecture : sections 2 et 3 ; API internes.

Documents : [PRD](../PRD.md), [Architecture](../Architecture.md), [Base de données](../Base-de-donnees.md), [API](../API.md). Retour au [registre](README.md).

