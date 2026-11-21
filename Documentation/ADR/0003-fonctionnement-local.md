# ADR-0003 — Privilégier une application locale sans serveur métier

Date : 10 novembre 2026  
Statut : Proposé — conditionné par DEC-02 et DEC-06  
Origine : échanges initiaux et architecture 0.1  
Validation : non encore enregistrée

## Contexte

Le PRD propose une bibliothèque hors ligne, sans compte nécessaire, et le contrôle des données personnelles.

## Décision

Conserver livres, positions et préférences sur l’appareil. Ne pas créer de serveur métier ni d’API REST pour ce périmètre. Limiter le réseau applicatif au téléchargement explicite de modèles autorisés ; ouvrir les liens choisis par l’utilisateur dans le système. Ne pas introduire de secours TTS distant silencieux.

## Alternatives considérées

Backend central : facilite certains services mais impose disponibilité réseau et gestion d’identité. Mode hybride : possible ultérieurement avec exigences de consentement et de synchronisation.

## Conséquences et compromis

Le fonctionnement local réduit les transmissions. Il ne fournit ni synchronisation ni restauration après perte de l’appareil. La faisabilité du TTS local reste une condition à vérifier.

## Validation attendue

Tester les parcours locaux en mode avion, après préparation des modèles, et inspecter les requêtes lors de l’ouverture d’un EPUB avec ressources distantes.

## Conditions de réexamen

Validation d’un besoin de synchronisation ou impossibilité démontrée de satisfaire les besoins TTS locaux ; réviser le PRD avant changement.

## Traçabilité

PRD : SEC-07, SEC-09, QUAL-06, DEC-02/06 ; Architecture : sections 1 et 7.

Documents : [PRD](../PRD.md), [Architecture](../Architecture.md), [Base de données](../Base-de-donnees.md), [API](../API.md). Retour au [registre](README.md).

