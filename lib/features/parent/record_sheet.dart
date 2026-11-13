import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/board.dart';
import '../../services/audio_recorder.dart';
import '../../services/recording_player.dart';
import '../../services/telemetry_service.dart';
import '../board/board_providers.dart';

/// Parent-facing display names, one entry per supportedLanguages member.
/// Shared with the language dropdown in parent_screen.dart (Task 10).
const languageDisplayNames = {
  'en': 'English',
  'ur': 'اردو',
  'ar': 'العربية',
  'fr': 'Français',
  'es': 'Español',
};

void showRecordSheet(BuildContext context, WidgetRef ref, SymbolCard card) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecordSheet(card: card),
  );
}

class _RecordSheet extends ConsumerStatefulWidget {
  const _RecordSheet({required this.card});
  final SymbolCard card;
  @override
  ConsumerState<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends ConsumerState<_RecordSheet> {
  // Rows derive from supportedLanguages — no per-language list here.
  static const _maxSeconds = 10;

  String? _recordingLang;
  int _elapsed = 0;
  Timer? _ticker;
  // Cached at the moment recording starts so a hot mic can be stopped from
  // dispose() without touching `ref` (unsafe once the widget is unmounted).
  Recorder? _activeRecorder;
  String? _activeTmpPath;
  late final TextEditingController _en;
  late final TextEditingController _ur;

  bool get _isCustom => widget.card.photoPath != null;

  @override
  void initState() {
    super.initState();
    _en = TextEditingController(text: widget.card.labels['en'] ?? '');
    _ur = TextEditingController(text: widget.card.labels['ur'] ?? '');
  }

  @override
  void dispose() {
    // Dismissal via barrier tap / swipe-down never runs rec-close's handler,
    // so this is the only place that catches those routes. Fire-and-forget:
    // dispose() can't be async, and by now `ref`/`context` are unsafe to
    // touch, which is exactly why the cached _activeRecorder/_activeTmpPath
    // fields (not ref.read) drive the cleanup.
    unawaited(_cancelActiveRecording());
    _en.dispose();
    _ur.dispose();
    super.dispose();
  }

  /// Stops a mic left running when the sheet closes by any route other than
  /// an explicit save. Cancels the ticker, stops the recorder, best-effort
  /// deletes the orphaned .tmp.m4a file, and deliberately never calls
  /// setRecording — close-while-recording is a cancel, not a save. Safe to
  /// call with nothing active (no-op) and safe to call from dispose() since
  /// it never touches `ref`, `context`, or setState.
  Future<void> _cancelActiveRecording() async {
    _ticker?.cancel();
    final lang = _recordingLang;
    final recorder = _activeRecorder;
    final cachedTmpPath = _activeTmpPath;
    _recordingLang = null;
    _activeRecorder = null;
    _activeTmpPath = null;
    if (lang == null || recorder == null) return;
    final stoppedPath = await recorder.stop();
    final tmpPath = stoppedPath ?? cachedTmpPath;
    if (tmpPath == null) return;
    try {
      File(tmpPath).deleteSync();
    } catch (_) {} // already gone / never created — nothing to clean up
  }

  /// The live card from the provider, so recording changes render immediately.
  SymbolCard get _card {
    final board = ref.watch(boardNotifierProvider).value;
    if (board == null) return widget.card;
    for (final cat in board.categories) {
      for (final c in cat.cards) {
        if (c.id == widget.card.id) return c;
      }
    }
    return widget.card;
  }

  Future<void> _start(String lang) async {
    final recorder = ref.read(recorderProvider);
    if (!await recorder.hasPermission()) return;
    final docs = ref.read(docsDirProvider);
    Directory('${docs.path}/recordings').createSync(recursive: true);
    // Extension MUST stay a valid audio container: on iOS, AVAudioRecorder
    // infers the output container format from the URL's path extension
    // (record_ios calls AVAudioRecorder(url:settings:) directly), so a
    // `.tmp` extension produces an unparseable file even though the bytes
    // get renamed to `.m4a` afterward. `.tmp.m4a` keeps the tmp-then-rename
    // safety net while giving the recorder a real `.m4a` extension to work
    // with. Android is unaffected (MediaRecorder takes an explicit format).
    final tmpPath = '${docs.path}/recordings/${widget.card.id}_$lang.tmp.m4a';
    await recorder.start(tmpPath);
    if (!mounted) return;
    _activeRecorder = recorder;
    _activeTmpPath = tmpPath;
    setState(() {
      _recordingLang = lang;
      _elapsed = 0;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed >= _maxSeconds) _stop(lang);
    });
  }

  Future<void> _stop(String lang) async {
    _ticker?.cancel();
    final Recorder recorder = _activeRecorder ?? ref.read(recorderProvider);
    final tmpPath = await recorder.stop();
    _activeRecorder = null;
    _activeTmpPath = null;
    if (!mounted) return;
    setState(() => _recordingLang = null);
    if (tmpPath == null) return;
    final finalPath = tmpPath.replaceFirst(RegExp(r'\.tmp\.m4a$'), '.m4a');
    try {
      File(tmpPath).renameSync(finalPath);
    } catch (_) {
      return; // failed save = no recording; card unchanged
    }
    await ref.read(boardNotifierProvider.notifier).setRecording(
        widget.card.id, lang, 'recordings/${widget.card.id}_$lang.m4a');
    ref.read(telemetryProvider).log(ParentEvent.recordingCreated,
        params: {'language': lang});
  }

  Future<void> _play(String lang) async {
    final rel = _card.recordings[lang];
    if (rel == null) return;
    final docs = ref.read(docsDirProvider);
    await ref.read(recordingPlayerProvider).play('${docs.path}/$rel');
  }

  Future<void> _delete(String lang) async {
    final rel = _card.recordings[lang];
    if (rel != null) {
      final docs = ref.read(docsDirProvider);
      try {
        File('${docs.path}/$rel').deleteSync();
      } catch (_) {}
    }
    await ref
        .read(boardNotifierProvider.notifier)
        .removeRecording(widget.card.id, lang);
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    return Padding(
      padding: EdgeInsetsDirectional.only(
          start: 16,
          end: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      // Five language rows + label fields outgrow small screens — scroll.
      child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
              child: Text(card.labels['en'] ?? card.id,
                  style: Theme.of(context).textTheme.titleMedium)),
          IconButton(
            key: const ValueKey('rec-close'),
            icon: const Icon(Icons.close),
            onPressed: () async {
              await _cancelActiveRecording();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ]),
        for (final lang in supportedLanguages)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
            child: Row(children: [
              SizedBox(width: 72, child: Text(languageDisplayNames[lang]!)),
              if (_recordingLang == lang) ...[
                Text('${_elapsed}s'),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: ValueKey('rec-stop-$lang'),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  onPressed: () => _stop(lang),
                ),
              ] else ...[
                OutlinedButton.icon(
                  key: ValueKey('rec-start-$lang'),
                  icon: const Icon(Icons.mic),
                  label: Text(card.recordings[lang] == null
                      ? 'Record'
                      : 'Re-record'),
                  onPressed:
                      _recordingLang == null ? () => _start(lang) : null,
                ),
                if (card.recordings[lang] != null) ...[
                  IconButton(
                    key: ValueKey('rec-play-$lang'),
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => _play(lang),
                  ),
                  IconButton(
                    key: ValueKey('rec-delete-$lang'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(lang),
                  ),
                ],
              ],
            ]),
          ),
        if (_isCustom) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('rec-label-en'),
            controller: _en,
            decoration: const InputDecoration(labelText: 'Label (English)'),
          ),
          TextField(
            key: const ValueKey('rec-label-ur'),
            controller: _ur,
            decoration: const InputDecoration(labelText: 'Label (اردو)'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: const ValueKey('rec-save-labels'),
              onPressed: () async {
                await _cancelActiveRecording();
                await ref
                    .read(boardNotifierProvider.notifier)
                    .setCustomLabels(widget.card.id, en: _en.text, ur: _ur.text);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ])),
    );
  }
}
