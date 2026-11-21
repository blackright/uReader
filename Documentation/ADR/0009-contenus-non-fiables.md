# ADR-0009 — Traiter les livres importés comme des entrées non fiables

Date : 10 novembre 2026  
Statut : Proposé — concrétisation de SEC-01 à SEC-06  
Origine : échanges initiaux et architecture 0.1  
Validation : non encore enregistrée

## Contexte

Un EPUB peut contenir archive hostile, scripts, liens et ressources distantes. Le rendu ne doit pas transformer l’ouverture d’un livre en exécution de code ou requêtes réseau.

## Décision

Borner copie, extraction, XML, images et traitement ; rejeter traversées de chemins, liens d’archive dangereux et entités externes. Assainir HTML/CSS, supprimer les contenus actifs et interdire le réseau du document. Autoriser seulement les liens http/https ouverts par action explicite dans le système. Ne choisir un moteur de rendu qu’après preuve d’isolation et d’accessibilité.

## Alternatives considérées

Afficher le document brut avec scripts désactivés uniquement : ne couvre pas archives, CSS ni ressources distantes. Bloquer tout contenu riche : simplifie certains risques mais dégrade la lecture et doit être évalué comme compromis.

## Conséquences et compromis

L’import peut refuser des ouvrages trop complexes ou volumineux avec explication. La fidélité du rendu est limitée par la politique d’assainissement. Les seuils précis restent à fixer avant recette.

## Validation attendue

Corpus hostile : traversée, bombe de décompression, XML externe, CSS/HTML/SVG actif, ressources de suivi, liens dangereux. Vérifier absence d’écriture hors racine, réseau et exécution. Les scripts de confiance éventuels du moteur doivent être isolés du livre.

## Conditions de réexamen

Un moteur exige un pont privilégié exposé au livre, ou une évolution de format exige de revoir les règles d’assainissement.

## Traçabilité

PRD : SEC-01 à SEC-06 ; Architecture : sections 4 et 7.

Documents : [PRD](../PRD.md), [Architecture](../Architecture.md), [Base de données](../Base-de-donnees.md), [API](../API.md). Retour au [registre](README.md).

