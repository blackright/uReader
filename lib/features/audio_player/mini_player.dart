import 'package:flutter/material.dart';

import 'player_presenter.dart';
import '../listening/playback_coordinator.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.presenter, required this.onOpen});
  final PlayerPresenter presenter;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: presenter,
    builder: (context, _) {
      if (!presenter.miniVisible) return const SizedBox.shrink();
      final playing =
          presenter.state == PlaybackState.playing ||
          presenter.state == PlaybackState.preparing;
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.headphones),
            ),
            Expanded(
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        presenter.book?.title ?? 'Lecture du livre',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        presenter.status,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: playing ? 'Pause' : 'Reprendre l’écoute',
              onPressed: presenter.playPause,
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: 'Ouvrir le player',
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_full),
            ),
          ],
        ),
      );
    },
  );
}
