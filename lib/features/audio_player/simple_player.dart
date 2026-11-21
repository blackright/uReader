import 'package:flutter/material.dart';

import '../listening/playback_coordinator.dart';
import 'player_presenter.dart';

class SimplePlayer extends StatelessWidget {
  const SimplePlayer({
    super.key,
    required this.presenter,
    required this.onSeek,
    required this.onShowHeard,
  });
  final PlayerPresenter presenter;
  final VoidCallback onSeek;
  final VoidCallback? onShowHeard;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: presenter.playPause,
        icon: Icon(
          presenter.state == PlaybackState.playing ||
                  presenter.state == PlaybackState.preparing
              ? Icons.pause
              : Icons.play_arrow,
        ),
        label: Text(
          presenter.state == PlaybackState.playing ||
                  presenter.state == PlaybackState.preparing
              ? 'Pause'
              : 'Lecture',
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => presenter.move(false),
        icon: const Icon(Icons.skip_previous),
        label: const Text('Paragraphe précédent'),
      ),
      OutlinedButton.icon(
        onPressed: () => presenter.move(true),
        icon: const Icon(Icons.skip_next),
        label: const Text('Paragraphe suivant'),
      ),
      OutlinedButton(
        onPressed: onSeek,
        child: const Text('Choisir un passage'),
      ),
      OutlinedButton(
        onPressed: onShowHeard,
        child: const Text('Afficher le passage entendu'),
      ),
      TextButton(onPressed: presenter.owner.stop, child: const Text('Arrêter')),
    ],
  );
}
