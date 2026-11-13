import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/purchase_service.dart';
import '../../services/settings_store.dart';

/// Store-channel-only "Support Bolo" section for parent mode. Core
/// communication is never gated; this buys the insights PDF export and
/// grandfathered access to future premium extras.
class SupporterSection extends ConsumerWidget {
  const SupporterSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked =
        ref.watch(settingsProvider).value?.supporterUnlocked ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Support Bolo', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      if (unlocked)
        const Text(
            'Thank you for supporting Bolo. The insights report export is unlocked.')
      else ...[
        const Text(
            "Bolo's communication features are free forever. A one-time supporter unlock adds the shareable insights report (PDF for therapists) and any future extras."),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton(
            key: const ValueKey('supporter-buy'),
            onPressed: () => ref.read(purchaseServiceProvider).buy(),
            child: const Text('Become a supporter'),
          ),
          const SizedBox(width: 12),
          TextButton(
            key: const ValueKey('supporter-restore'),
            onPressed: () => ref.read(purchaseServiceProvider).restore(),
            child: const Text('Restore purchase'),
          ),
        ]),
      ],
    ]);
  }
}
