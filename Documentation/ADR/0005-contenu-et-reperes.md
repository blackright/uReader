# ADR-0005 — Partager un contenu canonique et des repères stables

Date : 10 novembre 2026  
Statut : Proposé — prototype de rendu nécessaire  
Origine : échanges initiaux et architecture 0.1  
Validation : non encore enregistrée

## Contexte

Les changements de police et l’alternance texte/audio rendent les numéros de page insuffisants pour la reprise.

## Décision

Créer à l’import un contenu canonique versionné, ordonné en ressources et blocs. Utiliser un Locator comprenant livre, version, ressource, bloc et offset UTF-16 validé. Partager ces repères entre rendu, recherche, signets et TTS. Conserver séparément les positions visuelle et audio ; ne les déplacer ensemble que par une commande explicite.

## Alternatives considérées

Numéro de page : instable avec la mise en forme. Pourcentage seul : imprécis. Ancrages propres au moteur de rendu uniquement : dépendance forte et correspondance TTS à reconstruire.

## Conséquences et compromis

Une représentation commune facilite la continuité mais nécessite un normaliseur et une correspondance avec le rendu. Les mises à jour du normaliseur exigent migration ou maintien de l’ancien format ; pas de renormalisation silencieuse.

## Validation attendue

Tester sélection et reprise après changements de police/orientation, recherche pendant l’écoute, caractères Unicode et changement de version canonique. Le moteur de rendu reste à sélectionner.

## Conditions de réexamen

Le prototype ne conserve pas correctement l’ordre de lecture ou la correspondance document/blocs.

## Traçabilité

PRD : F-06, F-14, RM-07 à RM-11 ; Architecture : section 4.

Documents : [PRD](../PRD.md), [Architecture](../Architecture.md), [Base de données](../Base-de-donnees.md), [API](../API.md). Retour au [registre](README.md).

