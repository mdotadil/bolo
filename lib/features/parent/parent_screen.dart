import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/board.dart';
import '../../services/app_channel.dart';
import '../../services/backup_service.dart';
import '../../services/settings_store.dart';
import '../../services/telemetry_service.dart';
import '../board/board_providers.dart';
import 'about_page.dart';
import 'add_card_sheet.dart';
import 'insights_section.dart';
import 'record_sheet.dart';
import 'supporter_section.dart';
import 'type_to_speak.dart';

class ParentScreen extends ConsumerStatefulWidget {
  const ParentScreen({super.key});
  @override
  ConsumerState<ParentScreen> createState() => _ParentScreenState();
}

class _ParentScreenState extends ConsumerState<ParentScreen> {
  int _categoryIndex = 0;
  double? _pendingRate;

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(boardNotifierProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Parent mode')),
      body: boardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load board: $e')),
        data: (board) {
          final category = board.categories[_categoryIndex];
          return ListView(children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  const Text('Board language'),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    key: const ValueKey('language-switch'),
                    value: board.activeLanguage,
                    items: [
                      for (final lang in supportedLanguages)
                        DropdownMenuItem(
                            value: lang,
                            child: Text(languageDisplayNames[lang]!)),
                    ],
                    onChanged: (lang) {
                      if (lang == null) return;
                      ref
                          .read(boardNotifierProvider.notifier)
                          .setActiveLanguage(lang);
                      ref.read(telemetryProvider).log(
                          ParentEvent.languageChanged,
                          params: {'language': lang});
                    },
                  ),
                ]),
                FutureBuilder<bool>(
                  future: ref
                      .read(speechServiceProvider)
                      .languageAvailable(board.activeLanguage),
                  builder: (context, snap) => snap.data == false
                      ? Padding(
                          padding: const EdgeInsetsDirectional.only(top: 4),
                          child: Text(
                            '${languageDisplayNames[board.activeLanguage]} voice not available on this phone — recordings will be used.',
                            key: const ValueKey('voice-unavailable-note'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Row(children: [
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _categoryIndex,
                    items: [
                      for (var i = 0; i < board.categories.length; i++)
                        DropdownMenuItem(
                            value: i,
                            child: Text(board.categories[i].names[board.activeLanguage] ??
                                board.categories[i].names['en'] ??
                                ''))
                    ],
                    onChanged: (i) => setState(() => _categoryIndex = i ?? 0),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () =>
                      showAddCardSheet(context, ref, category.id),
                  icon: const Icon(Icons.add),
                  label: const Text('Add card'),
                ),
              ]),
            ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorderItem: (oldIndex, newIndex) => ref
                  .read(boardNotifierProvider.notifier)
                  .reorderCard(category.id, oldIndex, newIndex),
              children: [
                for (final card in category.cards)
                  _cardRow(board, card),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Row(children: [
                const Text('Speech speed'),
                Expanded(
                  child: Slider(
                    key: const ValueKey('rate-slider'),
                    value: _pendingRate ?? board.speechRate,
                    min: 0.3,
                    max: 0.7,
                    onChanged: (v) => setState(() => _pendingRate = v),
                    onChangeEnd: (v) async {
                      await ref
                          .read(boardNotifierProvider.notifier)
                          .setSpeechRate(v);
                      if (!mounted) return;
                      setState(() => _pendingRate = null);
                    },
                  ),
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: 12),
              child: TypeToSpeak(),
            ),
            const Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: 12),
              child: InsightsSection(),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('backup-button'),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Backup'),
                    onPressed: () async {
                      final docs = ref.read(docsDirProvider);
                      final telemetry = ref.read(telemetryProvider);
                      await ref.read(usageStoreProvider).flush();
                      final file =
                          await BackupService(docs).createBackup();
                      await SharePlus.instance.share(
                          ShareParams(files: [XFile(file.path)]));
                      telemetry.log(ParentEvent.backupCreated);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('restore-button'),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Restore'),
                    onPressed: () => _restoreFlow(context),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const ValueKey('about-privacy'),
                  icon: const Icon(Icons.privacy_tip_outlined),
                  label: const Text('About and privacy'),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutPage())),
                ),
              ),
            ),
            if (appChannel == AppChannel.store)
              Padding(
                padding:
                    const EdgeInsetsDirectional.symmetric(horizontal: 12),
                child: SwitchListTile(
                  key: const ValueKey('diagnostics-toggle'),
                  contentPadding: EdgeInsetsDirectional.zero,
                  title: const Text('Share anonymous diagnostics'),
                  subtitle: const Text(
                      'Crash reports and parent-mode feature counts. Never her words, recordings, or photos.'),
                  value:
                      ref.watch(settingsProvider).value?.telemetryEnabled ??
                          true,
                  onChanged: (v) async {
                    await ref
                        .read(settingsProvider.notifier)
                        .setTelemetryEnabled(v);
                    // Safe: this branch only renders in the store channel,
                    // where main() has initialized Firebase.
                    await FirebaseCrashlytics.instance
                        .setCrashlyticsCollectionEnabled(v);
                    await FirebaseAnalytics.instance
                        .setAnalyticsCollectionEnabled(v);
                  },
                ),
              ),
            if (appChannel == AppChannel.store)
              const Padding(
                padding:
                    EdgeInsetsDirectional.symmetric(horizontal: 12),
                child: SupporterSection(),
              ),
          ]);
        },
      ),
    );
  }

  Widget _cardRow(Board board, SymbolCard card) {
    return ListTile(
      key: ValueKey('row-${card.id}'),
      leading: SizedBox(width: 40, height: 40, child: _thumb(card)),
      title: Text(card.labels[board.activeLanguage] ?? card.labels['en'] ?? ''),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: ValueKey('mic-${card.id}'),
          icon: const Icon(Icons.mic_none),
          onPressed: () => showRecordSheet(context, ref, card),
        ),
        Semantics(
          identifier: 'switch-${card.id}',
          child: Switch(
            key: ValueKey('switch-${card.id}'),
            value: !card.hidden,
            onChanged: (_) =>
                ref.read(boardNotifierProvider.notifier).toggleHidden(card.id),
          ),
        ),
      ]),
    );
  }

  Widget _thumb(SymbolCard card) {
    if (card.photoPath != null) {
      return Image.file(File(card.photoPath!),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink());
    }
    if (card.symbolAsset != null) return SvgPicture.asset(card.symbolAsset!);
    return const SizedBox.shrink();
  }

  Future<void> _restoreFlow(BuildContext context) async {
    const typeGroup = XTypeGroup(label: 'Bolo backup', extensions: ['bolo']);
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('restore-confirm'),
        title: const Text('Restore backup?'),
        content: Text(
            'This replaces the current board, photos, and recordings with the backup "${picked.name}". This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final telemetry = ref.read(telemetryProvider);
    try {
      await BackupService(ref.read(docsDirProvider))
          .restore(File(picked.path));
      telemetry.log(ParentEvent.backupRestored);
    } on FormatException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Restore failed — your board may be incomplete. '
              'Try again or restore another backup.')));
    } finally {
      // Reload from disk on every post-confirmation attempt — success,
      // FormatException, or anything else — so the UI never keeps showing
      // stale in-memory state after a restore that touched disk.
      ref.invalidate(boardNotifierProvider);
    }
  }
}
