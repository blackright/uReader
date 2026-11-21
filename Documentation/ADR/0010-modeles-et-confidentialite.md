# ADR-0010 — Vérifier les modèles et limiter les données conservées

Date : 10 novembre 2026  
Statut : Proposé — politique de distribution à préciser  
Origine : échanges initiaux et architecture 0.1  
Validation : non encore enregistrée

## Contexte

Les modèles téléchargés sont une dépendance de confiance ; diagnostics, caches et sauvegardes peuvent exposer les lectures de l’utilisateur.

## Décision

Installer uniquement après action explicite, depuis un manifeste embarqué de confiance ou signé avec clé épinglée. Contrôler URLs et redirections, taille et hash avant activation atomique. Conserver les modèles précédemment utilisables lors d’un échec. Exclure les données de lecture des sauvegardes automatiques, les contenus/chemins des logs et toute télémétrie distante par défaut.

## Alternatives considérées

HTTPS et hash obtenus du même canal seuls : ne définissent pas une chaîne de provenance indépendante. Téléchargement arbitraire par URL : surface de confiance élargie. Sauvegarde automatique globale : contredit la politique proposée.

## Conséquences et compromis

Mises à jour et rotation de clés demandent une procédure documentée. L’absence de sauvegarde distante implique une perte possible après désinstallation ou perte de l’appareil. Aucun chiffrement applicatif additionnel ni effacement physique garanti n’est promis.

## Validation attendue

Tester modèle altéré, téléchargement interrompu, redirection hors liste, reprise d’installation, suppression avec session active et configuration des sauvegardes. Fixer rétention des diagnostics et plafonds de cache avant livraison.

## Conditions de réexamen

Introduction de synchronisation, changement de distribution des modèles, rotation de clés ou nouveau besoin de protection au repos.

## Traçabilité

PRD : SEC-07 à SEC-12, section 9 ; Architecture : sections 7 et 8.

Documents : [PRD](../PRD.md), [Architecture](../Architecture.md), [Base de données](../Base-de-donnees.md), [API](../API.md). Retour au [registre](README.md).

