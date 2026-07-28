import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../board/board_providers.dart';
import 'photo_picker.dart';

void showAddCardSheet(BuildContext context, WidgetRef ref, String categoryId) {
  final controller = TextEditingController();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      var toMore = false;
      return StatefulBuilder(
        builder: (context, setSheetState) => Padding(
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
            SwitchListTile(
              key: const ValueKey('add-card-more-toggle'),
              contentPadding: EdgeInsetsDirectional.zero,
              title: const Text('Put on More page'),
              value: toMore,
              onChanged: (v) => setSheetState(() => toMore = v),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('add-card-camera'),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Take photo'),
                  onPressed: () => _pick(sheetContext, ref, categoryId,
                      controller.text, fromCamera: true, toMorePage: toMore),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('add-card-gallery'),
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('Choose photo'),
                  onPressed: () => _pick(sheetContext, ref, categoryId,
                      controller.text, fromCamera: false, toMorePage: toMore),
                ),
              ),
            ]),
          ]),
        ),
      );
    },
  );
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
  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
}
