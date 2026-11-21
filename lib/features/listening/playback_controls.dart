import 'package:flutter/material.dart';

import '../../domain/content.dart';
import 'playback_coordinator.dart';

/// État livré avant G0 : aucune commande ne déclenche une synthèse de substitution.
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({super.key, this.coordinator, this.text, this.onPlay});
  final PlaybackCoordinator? coordinator;
  final DemoText? text;
  final Future<void> Function()? onPlay;

  @override
  Widget build(BuildContext context) {
    final owner = coordinator;
    if (owner != null) {
      return ListenableBuilder(
        listenable: owner,
        builder: (context, _) {
          final active = owner.textId == text?.id;
          final status = owner.state;
          final label = switch (status) {
            PlaybackState.stopped => 'Lecture arrêtée',
            PlaybackState.preparing => 'Préparation de la voix…',
            PlaybackState.playing => 'Lecture en cours',
            PlaybackState.paused => 'Lecture en pause',
            PlaybackState.completed => 'Lecture terminée',
            PlaybackState.error =>
              owner.error?.message ?? 'Écoute indisponible.',
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  owner.textId == null && text == null
                      ? 'Choisissez un texte pour écouter.'
                      : (!active && owner.textId != null
                            ? 'Écoute d’un autre texte. $label'
                            : label),
                ),
              ),
              if (owner.positionError != null)
                Semantics(
                  liveRegion: true,
                  child: const Text(
                    'La position audio n’a pas été sauvegardée. La reprise utilisera le dernier repère confirmé.',
                  ),
                ),
              if (text != null || owner.textId != null)
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed:
                          text != null &&
                              (!active ||
                                  [
                                    PlaybackState.stopped,
                                    PlaybackState.completed,
                                    PlaybackState.error,
                                  ].contains(status))
                          ? (onPlay ?? () => owner.play(text!))
                          : null,
                      child: const Text('Écouter'),
                    ),
                    OutlinedButton(
                      onPressed: status == PlaybackState.paused
                          ? owner.resume
                          : [
                              PlaybackState.preparing,
                              PlaybackState.playing,
                            ].contains(status)
                          ? owner.pause
                          : null,
                      child: Text(
                        status == PlaybackState.paused ? 'Reprendre' : 'Pause',
                      ),
                    ),
                    OutlinedButton(
                      onPressed:
                          owner.textId != null &&
                              status != PlaybackState.stopped
                          ? owner.stop
                          : null,
                      child: const Text('Arrêter'),
                    ),
                    OutlinedButton(
                      onPressed:
                          owner.textId != null &&
                              [
                                PlaybackState.playing,
                                PlaybackState.paused,
                              ].contains(status)
                          ? owner.previous
                          : null,
                      child: const Text('Précédent'),
                    ),
                    OutlinedButton(
                      onPressed:
                          owner.textId != null &&
                              [
                                PlaybackState.playing,
                                PlaybackState.paused,
                              ].contains(status)
                          ? owner.next
                          : null,
                      child: const Text('Suivant'),
                    ),
                  ],
                ),
            ],
          );
        },
      );
    }
    return Semantics(
      liveRegion: true,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Écoute indisponible : aucune voix française validée sur cet appareil. '
          'Vous pouvez continuer à lire les textes.',
        ),
      ),
    );
  }
}
