import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/telemetry_service.dart';
import '../board/board_providers.dart';
import 'photo_picker.dart';

void showAddCardSheet(BuildContext context, WidgetRef ref, String categoryId) {
  final controller = TextEditingController();
  // Owned OUTSIDE showModalBottomSheet's builder on purpose. The builder
  // closure below re-runs on any inherited-widget change it reads from
  // (it calls MediaQuery.viewInsetsOf, so keyboard show/hide alone
  // re-invokes it) — a `var` declared inside that closure would be
  // silently recreated as `false` on every such rebuild, discarding the
  // user's toggle. A ValueNotifier declared here, next to `controller`,
  // survives every rebuild of the sheet's subtree.
  final toMore = ValueNotifier<bool>(false);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsetsDirectional.only(
          start: 16,
          end: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const ValueKey('add-card-label'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Word to speak'),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: toMore,
          builder: (context, value, _) => SwitchListTile(
            key: const ValueKey('add-card-more-toggle'),
            contentPadding: EdgeInsetsDirectional.zero,
            title: const Text('Put on More page'),
            value: value,
            onChanged: (v) => toMore.value = v,
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('add-card-camera'),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take photo'),
              onPressed: () => _pick(sheetContext, ref, categoryId,
                  controller.text,
                  fromCamera: true, toMorePage: toMore.value),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('add-card-gallery'),
              icon: const Icon(Icons.photo_outlined),
              label: const Text('Choose photo'),
              onPressed: () => _pick(sheetContext, ref, categoryId,
                  controller.text,
                  fromCamera: false, toMorePage: toMore.value),
            ),
          ),
        ]),
      ]),
    ),
  ).whenComplete(toMore.dispose);
}

Future<void> _pick(BuildContext sheetContext, WidgetRef ref, String categoryId,
    String label,
    {required bool fromCamera, required bool toMorePage}) async {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return;
  final path = await ref.read(photoPickerProvider).pickPhoto(
      fromCamera: fromCamera,
      saveDir: ref.read(boardStoreProvider).photosDir);
  if (path == null) return; // user cancelled the picker
  await ref.read(boardNotifierProvider.notifier).addCustomCard(
      categoryId: categoryId,
      label: trimmed,
      photoPath: path,
      toMorePage: toMorePage);
  ref.read(telemetryProvider).log(ParentEvent.customCardAdded);
  if (toMorePage) {
    ref.read(telemetryProvider).log(ParentEvent.morePageConfigured);
  }
  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
}
