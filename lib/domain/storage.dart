import 'app_error.dart';

class BundleFile {
  BundleFile({
    required this.relativePath,
    required this.byteSize,
    required this.sha256,
  }) {
    validateRelativePath(relativePath);
    if (byteSize < 0 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const AppError(ErrorCode.invalidContent);
    }
  }
  final String relativePath;
  final int byteSize;
  final String sha256;
}

void validateRelativePath(String relative) {
  final parts = relative.split('/');
  final reserved = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  );
  if (parts.any(
    (part) =>
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$').hasMatch(part) ||
        part.contains('..') ||
        part.endsWith('.') ||
        reserved.hasMatch(part),
  )) {
    throw const AppError(ErrorCode.unsafePath);
  }
}

class BundleDescriptor {
  BundleDescriptor({
    required this.id,
    required this.version,
    required this.manifestDigest,
    required List<BundleFile> files,
  }) : files = List.unmodifiable(files) {
    requireIdentifier(id);
    requireIdentifier(version);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(manifestDigest) ||
        files.isEmpty ||
        files.map((f) => f.relativePath.toLowerCase()).toSet().length !=
            files.length) {
      throw const AppError(ErrorCode.invalidContent);
    }
  }
  final String id;
  final String version;
  final String manifestDigest;
  final List<BundleFile> files;
  String get directory => 'models/$id/$version';
}

enum OperationKind { install, delete }

enum OperationPhase { pending, published, error }

class JournalOperation {
  JournalOperation({
    required this.id,
    required this.kind,
    required this.bundleId,
    required this.bundleVersion,
    required this.manifestDigest,
    this.phase = OperationPhase.pending,
    this.errorCode,
  }) {
    requireIdentifier(id);
    requireIdentifier(bundleId);
    requireIdentifier(bundleVersion);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(manifestDigest)) {
      throw const AppError(ErrorCode.invalidContent);
    }
  }
  final String id;
  final OperationKind kind;
  final String bundleId;
  final String bundleVersion;
  final String manifestDigest;
  final OperationPhase phase;
  final ErrorCode? errorCode;
  String get stagingDirectory => 'staging/$id';
  String get finalDirectory => 'models/$bundleId/$bundleVersion';
}

abstract interface class OperationJournal {
  Future<List<JournalOperation>> pendingOperations();
  Future<void> saveOperation(JournalOperation operation);
  Future<void> markOperationError(String id, ErrorCode code);
  Future<void> forgetOperation(String id);
  Future<void> completeInstall(
    JournalOperation operation,
    BundleDescriptor verified,
  );
  Future<void> completeDelete(JournalOperation operation);
}

abstract interface class PrivateFiles {
  Future<List<String>> stagingDirectories();
  Future<bool> exists(String relative);
  Future<bool> verify(String relative, List<BundleFile> expected);
  Future<void> publish(String staging, String destination);
  Future<void> delete(String relative);
}

typedef BundleTrustResolver = Future<BundleDescriptor?> Function(
  String id,
  String version,
  String manifestDigest,
);
