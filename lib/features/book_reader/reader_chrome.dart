import 'package:flutter/material.dart';

/// Discrete navigation chrome. It does not own an audio session or seek it.
class ReaderChromeFooter extends StatelessWidget {
  const ReaderChromeFooter({
    super.key,
    required this.label,
    this.progress,
    required this.previousLabel,
    required this.nextLabel,
    this.onPrevious,
    this.onNext,
    this.audioAction,
  });
  final String label, previousLabel, nextLabel;
  final double? progress;
  final VoidCallback? onPrevious, onNext;
  final Widget? audioAction;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .3,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?audioAction,
              Row(
                children: [
                  IconButton(
                    tooltip: previousLabel,
                    onPressed: onPrevious,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        if (progress != null)
                          Text(
                            '${(progress! * 100).floor()} % du texte',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: nextLabel,
                    onPressed: onNext,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    semanticsLabel: 'Progression dans le texte',
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
