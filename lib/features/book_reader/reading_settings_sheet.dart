import 'package:flutter/material.dart';

import '../../domain/book_reader.dart';
import '../../domain/reader_experience.dart';
import '../../app/reader_theme.dart';
import '../../app/highlight_colors.dart';

typedef ReadingSettings = ({
  ReaderPreferences reader,
  ExperiencePreferences experience,
});

class ReadingSettingsSheet extends StatefulWidget {
  const ReadingSettingsSheet({
    super.key,
    required this.preferences,
    required this.experience,
    required this.extended,
  });
  final ReaderPreferences preferences;
  final ExperiencePreferences experience;
  final bool extended;
  @override
  State<ReadingSettingsSheet> createState() => _ReadingSettingsSheetState();
}

class _ReadingSettingsSheetState extends State<ReadingSettingsSheet> {
  late double scale = widget.preferences.fontScale;
  late ReaderTheme theme = widget.preferences.theme;
  late ReaderMode mode = widget.experience.mode;
  late AudioPresentation presentation = widget.experience.presentation;
  late HighlightColor highlight = widget.experience.highlightColor;
  late double line = widget.experience.lineHeight,
      margins = widget.experience.margins;
  Widget choices<T>(
    String title,
    List<({T value, String label})> options,
    T value,
    void Function(T) change,
  ) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final o in options)
              ChoiceChip(
                label: Text(o.label),
                selected: value == o.value,
                onSelected: (_) => setState(() => change(o.value)),
              ),
          ],
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: ReaderVisualTheme.theme(dark: theme == ReaderTheme.dark),
    child: Builder(
      builder: (ctx) => Material(
        color: Theme.of(ctx).colorScheme.surface,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .85,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Réglages de lecture',
                    style: Theme.of(ctx).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(ctx).dividerColor),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Prendre le temps de lire.\nLa lumière traverse les feuilles.',
                      style: TextStyle(
                        backgroundColor: ReadingHighlight.resolve(highlight)
                            .withValues(alpha: .24),
                        fontFamily: 'serif',
                        fontSize: 18 * scale,
                        height: line,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Taille du texte : ${(scale * 100).round()} %'),
                  Slider(
                    value: scale,
                    min: .75,
                    max: 2,
                    divisions: 5,
                    label: '${(scale * 100).round()} %',
                    onChanged: (v) => setState(() => scale = v),
                  ),
                  const Text(
                    'La taille système reste appliquée en plus de ce réglage.',
                  ),
                  choices(
                    'Thème',
                    [
                      (value: ReaderTheme.light, label: 'Clair'),
                      (value: ReaderTheme.dark, label: 'Sombre'),
                    ],
                    theme,
                    (v) => theme = v,
                  ),
                  if (widget.extended) ...[
                    choices(
                      'Navigation',
                      [
                        (value: ReaderMode.paged, label: 'Pages'),
                        (value: ReaderMode.scroll, label: 'Défilement'),
                      ],
                      mode,
                      (v) => mode = v,
                    ),
                    choices(
                      'Interligne',
                      [
                        (value: 1.2, label: 'Serré'),
                        (value: 1.5, label: 'Confort'),
                        (value: 1.8, label: 'Aéré'),
                      ],
                      line,
                      (v) => line = v,
                    ),
                    choices(
                      'Marges',
                      [
                        (value: 12.0, label: 'Étroites'),
                        (value: 20.0, label: 'Moyennes'),
                        (value: 28.0, label: 'Larges'),
                      ],
                      margins,
                      (v) => margins = v,
                    ),
                  ],
                  choices(
                    'Couleur du surlignage',
                    [
                      (value: HighlightColor.yellow, label: 'Jaune'),
                      (value: HighlightColor.green, label: 'Vert'),
                      (value: HighlightColor.blue, label: 'Bleu'),
                      (value: HighlightColor.pink, label: 'Rose'),
                      (value: HighlightColor.purple, label: 'Violet'),
                    ],
                    highlight,
                    (v) => highlight = v,
                  ),
                  choices(
                    'Player audio',
                    [
                      (value: AudioPresentation.full, label: 'Complet'),
                      (value: AudioPresentation.simple, label: 'Simplifié'),
                    ],
                    presentation,
                    (v) => presentation = v,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, (
                      reader: ReaderPreferences(fontScale: scale, theme: theme),
                      experience: ExperiencePreferences(
                        mode: mode,
                        lineHeight: line,
                        margins: margins,
                        followEnabled: widget.experience.followEnabled,
                        presentation: presentation,
                        highlightColor: highlight,
                      ),
                    )),
                    child: const Text('Appliquer'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
