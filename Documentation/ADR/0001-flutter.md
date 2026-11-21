# ADR-0001 — Utiliser Flutter pour l’application

Date : 10 novembre 2026  
Statut : Accepté — choix demandé par le porteur du projet  
Origine : échanges initiaux et architecture 0.1  
Validation : choix produit demandé ; détails techniques non validés

## Contexte

Le produit doit réunir bibliothèque, lecture visuelle et écoute dans une même application.

## Décision

Développer l’interface et les cas d’utilisation en Flutter/Dart. Encapsuler les fonctions propres à la plateforme derrière des adaptateurs. Cette décision ne fixe ni les plateformes de lancement ni leurs versions minimales.

## Alternatives considérées

Applications natives distinctes : intégration système directe mais duplication du produit. Application web : distribution simple mais contraintes différentes pour le stockage et l’audio local.

## Conséquences et compromis

Un socle applicatif partagé est possible. Le rendu, l’accessibilité et le cycle de vie audio nécessitent néanmoins des essais propres à chaque plateforme.

## Validation attendue

Créer un squelette compilable sur la plateforme retenue et vérifier navigation, accès aux fichiers et accessibilité. DEC-01 reste ouvert.

## Conditions de réexamen

Une contrainte démontrée de rendu, performance ou intégration native empêche un parcours P0.

## Traçabilité

PRD : choix Flutter, DEC-01 ; Architecture : sections 1 à 3.

Documents : [PRD](../PRD.md), [Architecture](../Architecture.md), [Base de données](../Base-de-donnees.md), [API](../API.md). Retour au [registre](README.md).

