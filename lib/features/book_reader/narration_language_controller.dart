enum NarrationLanguage { french, confirmationRequired, unsupported }

class NarrationLanguageController {
  static NarrationLanguage evaluate(List<String> languages) {
    final declared = languages
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
    if (declared.isEmpty || declared.length > 1 || declared.single == 'und') {
      return NarrationLanguage.confirmationRequired;
    }
    return declared.single.split('-').first == 'fr'
        ? NarrationLanguage.french
        : NarrationLanguage.unsupported;
  }
}
