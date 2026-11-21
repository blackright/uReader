enum ErrorCode {
  invalidContent,
  invalidLocator,
  invalidMessage,
  revisionConflict,
  storageUnavailable,
  storageLimitExceeded,
  unsafePath,
  resourceInUse,
  modelMissing,
  modelIntegrityFailed,
  engineUnavailable,
  unsupportedSchema,
  cancelled,
}

class AppError implements Exception {
  const AppError(this.code);
  final ErrorCode code;
  String get message => switch (code) {
    ErrorCode.invalidContent => 'Le contenu est invalide.',
    ErrorCode.invalidLocator => 'Ce passage ne peut pas être retrouvé.',
    ErrorCode.invalidMessage => 'Cette commande est invalide.',
    ErrorCode.revisionConflict => 'La position a été modifiée. Rechargez-la.',
    ErrorCode.storageUnavailable => 'Le stockage est indisponible. Réessayez.',
    ErrorCode.storageLimitExceeded => 'La taille autorisée est dépassée.',
    ErrorCode.unsafePath => 'Cet emplacement de stockage est refusé.',
    ErrorCode.resourceInUse =>
      'Cette ressource est utilisée. Arrêtez son utilisation.',
    ErrorCode.modelMissing =>
      'Aucune ressource vocale utilisable n’est installée.',
    ErrorCode.modelIntegrityFailed =>
      'La ressource vocale ne peut pas être vérifiée.',
    ErrorCode.engineUnavailable =>
      'La synthèse vocale n’est pas encore disponible.',
    ErrorCode.unsupportedSchema =>
      'Cette version des données ne peut pas être ouverte.',
    ErrorCode.cancelled => 'Opération annulée.',
  };
  @override
  String toString() => message;
}

void requireIdentifier(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$').hasMatch(value) ||
      value.contains('..') ||
      value.endsWith('.')) {
    throw const AppError(ErrorCode.invalidContent);
  }
}
