# ADR-0007 — Isoler Pocket TTS et conditionner son runtime mobile à un prototype

Date : 10 novembre 2026  
Statut : Accepté pour le choix Pocket TTS ; intégration proposée et à valider  
Origine : échanges initiaux et architecture 0.1  
Validation : choix produit demandé ; détails techniques non validés

## Contexte

Pocket TTS est demandé. Les capacités et performances attendues sur les appareils cibles ne sont pas encore démontrées.

## Décision

Définir SpeechEngine pour capacités, chargement local, synthèse, annulation et libération. Sélectionner runtime et transport FFI/canaux de plateforme après preuve sur appareil. Ne pas figer de binding mobile, format de modèle, langue ni seuil de performance sans vérification. Ne pas substituer un autre moteur ou un serveur sans décision explicite.

## Alternatives considérées

Couplage direct au runtime : réduit les contrats mais expose le domaine à ses contraintes. Service distant : change confidentialité et fonctionnement hors ligne. Autre moteur : nécessite une nouvelle décision produit.

## Conséquences et compromis

L’adaptateur permet les tests et une évolution du runtime. Il ne résout pas à lui seul le portage mobile ; ce point peut bloquer le périmètre TTS.

## Validation attendue

Produire un rapport avec appareil/version système, version du moteur et des modèles, langues/voix, licences, latence, mémoire, batterie et distribution. Vérifier libération et annulation. Aucune mesure n’est encore disponible.

## Conditions de réexamen

Le prototype échoue sur les appareils ou langues prioritaires, ou les licences de distribution ne conviennent pas.

## Traçabilité

PRD : F-09, RM-17, DEC-02/03 ; Architecture : section 6 ; API : contrat de synthèse.

Documents : [PRD](../PRD.md), [Architecture](../Architecture.md), [Base de données](../Base-de-donnees.md), [API](../API.md). Retour au [registre](README.md).

