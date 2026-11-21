import '../../domain/books.dart';
import 'epub_package_parser.dart';

abstract interface class EpubImportSource implements BookDocumentSource {
  String? get displayName;
  Future<({String sha256, int bytes})> copyAndHash(
    String handle, {
    void Function(int bytes)? progress,
  });
  Future<VerifiedEpubArchive> openArchive();
}
