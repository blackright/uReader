# ADR-0011 — Intégrer Kokoro SIWIS derrière SpeechEngine

Date : 25 novembre 2026. Statut : choix produit accepté pour développement ;
runtime Android et distribution à qualifier.

## Contexte et décision

Après comparaison privée sur Lupin P01–P20, le porteur demande que l'application
utilise Kokoro SIWIS avec les corrections lexicales minimales acceptées.
Cette demande constitue la décision explicite de changement de moteur exigée
par ADR-0007. Pocket reste le moteur courant tant que l'intégration n'est pas livrée.

Conserver SpeechEngine, le coordinateur unique, le player et la préparation
anticipée. Viser un export local des poids vérifiés vers ONNX Runtime existant,
avec phonémisation française embarquée à qualifier sur texte inédit. Aucun
serveur ni clonage vocal n'est ajouté. Le détail du frontend et les obligations
de distribution restent à résoudre ; aucun runtime précompilé n'est supposé
reproduire la voix française acceptée.

## Contrats et retour arrière

L'identité complète moteur/voix/modèle/préparation doit traverser la configuration,
les capacités et le cache. Rejeter les résultats tardifs après annulation, borner
les entrées et conserver la propriété/libération existantes des fichiers audio.
Un bundle absent ou altéré produit une indisponibilité explicite ; aucune
substitution silencieuse par Pocket n'est permise.

Conserver les repères source et le suivi de paragraphe. Une durée phonétique
ne constitue pas une preuve de synchronisation précise des mots. L'installation
doit vérifier les fichiers et conserver les données et l'ancienne voix pour un
retour arrière explicite. La taille maximale du nouveau bundle reste bornée.

## Validation et conséquences

Mesurer export, fidélité sonore, vitesse, mémoire et thermique avant activation
dans le lecteur normal. Figer les budgets mesurés avant la recette d'endurance.
Revoir les licences du frontend embarqué avant distribution ; ne pas modifier
implicitement la licence du projet. Les notes dimensionnelles manquantes et
les validations humaines reportées restent ouvertes.

Références : [décision](../../specs/004-french-narration-quality/decision.md),
[travaux Android](../../specs/004-french-narration-quality/android-integration.md).

## Alternatives et conditions de réexamen

Pocket seul ne livre pas le rendu demandé ; il reste un retour arrière explicite.
Un serveur changerait le fonctionnement autonome et la confidentialité : exclu.
Un autre runtime embarqué exigerait de prouver le même frontend français et
d'éviter une duplication incompatible d'ONNX Runtime : non retenu à ce stade.

Réexaminer si l'export n'est pas fidèle, si le frontend embarqué ne reproduit
pas les phonèmes attendus, si les licences ne conviennent pas à la distribution
ou si la synthèse soutenue ne suit pas la lecture sur Samsung. Ne pas masquer
ces échecs par une voix différente, une préparation complète du chapitre ou du
texte ignoré. Détails de la frontière :
[contrat Android](../../specs/004-french-narration-quality/contracts/android-kokoro.md).

## Précision du 26 novembre — prototype local

Le banc Samsung/API 29 reproduit les 54 entrées phonétiques et génère P05.
Cela ne qualifie pas G0 ni SC-003. Le profil `local_native_preview` conserve
donc `g0Verdict=not_evaluated` et requiert une preuve native distincte, une
sélection explicite du porteur et un manifeste embarqué dont le digest est
vérifié. Ce profil est bloqué hors développement : contrôles Dart product/profile
et contrôle natif FLAG_DEBUGGABLE. Le profil Pocket et son gate G0 restent inchangés.
Un manifeste sans preuve native ne rend pas la voix disponible. Le retour
d'écoute Android reste enregistré séparément ; il ne fournit pas de score absent.

Cette séparation concrétise l'intégration de développement demandée ; elle
n'annonce pas une livraison qualifiée et n'autorise pas une distribution dont
les licences n'ont pas été revues. Aucun fallback automatique entre profils.
