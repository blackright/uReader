import 'dart:math';

/// Process/isolate restarts and independent clients never reuse an in-flight ID.
String newEpubClientId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
