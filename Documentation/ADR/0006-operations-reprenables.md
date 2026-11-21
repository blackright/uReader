# ADR-0006 — Journaliser les opérations entre fichiers et base

Date : 10 novembre 2026  
Statut : Proposé  
Origine : échanges initiaux et architecture 0.1  
Validation : non encore enregistrée

## Contexte

Un arrêt peut survenir entre publication des fichiers et transaction SQL ; une transaction SQLite seule ne couvre pas ces deux stockages.

## Décision

Utiliser un staging privé, un journal d’opérations et des étapes idempotentes. Valider avant publication ; exposer uniquement les livres prêts. Réconcilier les opérations inachevées au redémarrage. Pour supprimer, arrêter l’audio, marquer deleting, retirer les fichiers puis les lignes. Conserver une opération reprenable en cas d’échec.

## Alternatives considérées

Supposer une transaction globale : garantie inexistante dans ce modèle. Nettoyage manuel : laisse des états incohérents. Stockage binaire entièrement en base : autre compromis documenté dans ADR-0004.

## Conséquences et compromis

L’utilisateur récupère une bibliothèque cohérente après interruption. La reprise et le nettoyage d’orphelins ajoutent des états à tester. Le fichier original sélectionné n’est jamais supprimé.

## Validation attendue

Injecter un arrêt à chaque étape d’import, suppression et migration ; répéter la reprise et vérifier absence de doublons, perte d’autres livres ou faux succès.

## Conditions de réexamen

Changement du modèle de stockage ou impossibilité de rendre une étape idempotente sans revoir son protocole.

## Traçabilité

PRD : RM-01 à RM-06, QUAL-04/05 ; Architecture : sections 5 et 8.

Documents : [PRD](../PRD.md), [Architecture](../Architecture.md), [Base de données](../Base-de-donnees.md), [API](../API.md). Retour au [registre](README.md).

