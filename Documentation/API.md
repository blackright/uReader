# API et contrats internes — uReader

Version : 0.1 — 10 novembre 2026  
Statut : contrats de conception, signatures Dart indicatives  
Référence : [Architecture](Architecture.md), [Base de données](Base-de-donnees.md)

## 1. Frontières

La première version locale n’expose aucun serveur HTTP, endpoint public, authentification serveur ou API REST. Les API ci-dessous sont des interfaces internes entre Flutter, domaine et adaptateurs. Les téléchargements de modèles sont des requêtes sortantes vers des ressources autorisées ; leurs URLs ne sont pas fournies par les livres.

## 2. Types communs

```dart
class Locator {
  final String bookId;
  final int contentVersion;
  final String resourceId;
  final String blockId;
  final int offsetUtf16;
}

class SessionToken {
  final String sessionId;
  final int generation;
}
```

Ces extraits omettent constructeurs et sérialisation. Les opérations retournent un `Result<T, AppError>` ; les flux publient des événements typés. Les listes sont paginées et les résultats longs sont annulables. Les chemins internes, handles natifs et exceptions brutes ne traversent pas la frontière vers l’interface utilisateur.

## 3. Services applicatifs

| Interface | Opération indicative | Contrat |
|---|---|---|
| `LibraryService` | `importBook(PickedFileHandle, CancelToken) → ImportResult` | Handle issu du sélecteur ; événements de progression ; résultat imported/existing ; annulation nettoyée |
| | `watchBooks(BookQuery) → Stream<BookPage>` | Recherche et tri validés, pagination bornée, uniquement livres visibles |
| | `deleteBook(BookId) → DeleteResult` | Appelé après confirmation utilisateur ; arrêt audio, suppression rejouable ; succès uniquement après nettoyage |
| `ReaderService` | `open(BookId) → ReaderDocument` | Livre prêt et fichiers présents ; aucune exécution de contenu actif |
| | `navigate(Locator) → Locator` | Valide le repère ; retourne le repère résolu avec éventuel avertissement de repli |
| | `saveVisualPosition(Locator, expectedRevision) → Position` | Écriture visuelle uniquement, contrôle de concurrence |
| | `search(BookId, query, page, CancelToken) → SearchPage` | Résultats avec Locator et extrait affichable comme texte |
| `BookmarkService` | `add(Locator, label)`, `list(BookId)`, `remove(BookmarkId)` | Validation de cible ; label borné ; suppression idempotente |
| `ListeningService` | `play(BookId, Locator?) → SessionToken` | Si aucun repère : reprise audio valide, sinon repère visuel ; remplace la session précédente |
| | `pause()`, `stop()`, `previousSegment()`, `nextSegment()` | Commandes sérialisées au coordinateur unique ; comportement sûr sans session |
| | `seek(Locator)`, `setSpeed(double)` | Seek invalide l’ancienne génération ; vitesse dans la plage validée |
| | `setSleepTimer(Duration?)` | null annule ; durée positive et bornée ; remplace la minuterie existante |
| | `watchPlayback() → Stream<PlaybackSnapshot>` | Livre, session, état, repère réellement joué, vitesse, minuterie et erreur publique |
| `SettingsService` | `read()`, `update(ValidatedSettings)` | Validation typée, écriture atomique et notification des observateurs |
| `StorageService` | `usage()`, `clearAudioCache()` | Sépare livres/modèles/cache ; éléments actifs protégés ; résultat indique espace réellement libéré |
| `ModelService` | `listCapabilities()`, `install(ModelRef, CancelToken)`, `remove(ModelRef)` | Référence issue du manifeste de confiance ; téléchargement explicite ; refus si modèle utilisé sans arrêt préalable |

Les commandes système sont traduites vers `ListeningService` ; elles n’appellent pas un second lecteur. Les commandes de pause et arrêt répétées réussissent sans effet supplémentaire. Les répétitions de lecture ne doivent pas créer deux sessions concurrentes.

## 4. Adaptateurs techniques

| Port | Responsabilité |
|---|---|
| `BookRepository` | Métadonnées, requêtes paginées, contrainte de doublon et transactions |
| `PositionRepository` | Repères par mode, validation des références et révisions |
| `ContentRepository` | Blocs immuables, plages textuelles et correspondance vers les ressources |
| `PrivateFileStore` | Résolution contrôlée de chemins relatifs, staging, publication atomique et nettoyage |
| `ReaderEngine` | Charger le document assaini, naviguer vers un Locator, émettre sélection et position visuelle |
| `SpeechEngine` | Capacités réellement disponibles, chargement de modèle local, synthèse et annulation |
| `AudioPlayer` | Jouer des segments validés, exposer début/fin réellement joués et événements d’interruption |
| `TrustedModelDownloader` | URLs autorisées, limites réseau, vérification manifeste/hash et publication |

### Contrat de synthèse

```text
SpeechRequest
  token: SessionToken
  requestId: identifiant unique
  locatorRange: début et fin dans un bloc canonique
  text: texte local correspondant à cette plage
  model: identifiant + version vérifiés
  voiceId: voix compatible
  parameters: paramètres de génération versionnés

SpeechOutput
  token + requestId
  audioHandle: ressource locale détenue par l’adaptateur
  sampleRate + channels + encoding
  duration si connue
  locatorRange
```

Le coordinateur vérifie token, format audio, limites et plage avant publication. L’adaptateur ne choisit pas lui-même une autre langue, un modèle distant ou une voix de remplacement. `cancel(token)` est idempotent ; même si le runtime finit tardivement, le résultat n’est plus jouable. Aucun alignement temporel par mot n’est garanti.

### Pont natif éventuel

Le transport FFI ou canaux de plateforme reste à sélectionner par prototype. Le contrat doit être versionné et proposer `capabilities`, `loadModel`, `synthesize`, `cancel` et `dispose`. Les résultats volumineux passent par buffers bornés ou handles privés ; pas de texte ni audio dans les logs de transport. Les handles sont libérés sur succès, erreur et annulation. Ne pas supposer qu’un binding mobile officiel est disponible.

## 5. Erreurs publiques

| Code | Situation | Action proposée |
|---|---|---|
| `unsupported_format` / `protected_content` | Fichier hors périmètre | Choisir un fichier pris en charge |
| `invalid_book` / `import_limit_exceeded` | Contenu invalide ou limite de sécurité | Expliquer le refus sans exposer les chemins |
| `storage_full` / `storage_unavailable` | Copie ou sauvegarde impossible | Libérer de l’espace puis réessayer |
| `book_unavailable` / `invalid_locator` | Fichier absent ou repère invalide | Repli signalé si possible, sinon retour bibliothèque |
| `model_missing` / `model_integrity_failed` | Modèle absent ou refusé | Installer ou télécharger à nouveau explicitement |
| `language_unavailable` / `engine_unavailable` | Capacité TTS absente | Poursuivre visuellement ; aucune substitution distante |
| `audio_interrupted` / `synthesis_failed` | Écoute suspendue ou génération échouée | Reprise manuelle depuis le repère durable |
| `revision_conflict` | Sauvegarde obsolète | Recharger la version actuelle ; ne pas écraser silencieusement |
| `cancelled` | Annulation utilisateur | Terminer proprement, sans présenter une panne |

Chaque erreur comporte un code stable, une clé de message localisable, un indicateur de nouvelle tentative et éventuellement un identifiant de diagnostic non sensible. Une trace interne ne devient jamais un message utilisateur.

## 6. Tests de contrat prévus

Les faux adaptateurs doivent pouvoir simuler un modèle absent, une synthèse tardive après annulation, un disque saturé et une interruption système. Les tests vérifient notamment que l’UI et les commandes système observent la même session, que les erreurs ne déclenchent aucun appel réseau de secours et que les repères visuels et audio restent indépendants.

Une future API de synchronisation fera l’objet d’un document distinct : identité, autorisation par ressource, conflits, idempotence, chiffrement de transport et suppression distante devront alors être spécifiés avant ajout de routes.
