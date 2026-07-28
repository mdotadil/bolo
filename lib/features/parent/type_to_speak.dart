import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../board/board_providers.dart';

/// Parent tool: type anything, the phone speaks it in the active language.
/// Session-only recents; nothing is persisted.
class TypeToSpeak extends ConsumerStatefulWidget {
  const TypeToSpeak({super.key});
  @override
  ConsumerState<TypeToSpeak> createState() => _TypeToSpeakState();
}

class _TypeToSpeakState extends ConsumerState<TypeToSpeak> {
  final _controller = TextEditingController();
  final List<String> _recents = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _speak([String? text]) async {
    final t = (text ?? _controller.text).trim();
    if (t.isEmpty) return;
    final lang = ref.read(boardNotifierProvider).value?.activeLanguage ?? 'en';
    await ref.read(speechServiceProvider).speakText(t, language: lang);
    if (text == null) {
      setState(() {
        _recents.remove(t);
        _recents.insert(0, t);
        if (_recents.length > 10) _recents.removeLast();
        _controller.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Type to speak', style: Theme.of(context).textTheme.titleMedium),
      Row(children: [
        Expanded(
          child: TextField(
            key: const ValueKey('tts-field'),
            controller: _controller,
            decoration: const InputDecoration(hintText: 'Type a word or sentence'),
            onSubmitted: (_) => _speak(),
          ),
        ),
        IconButton(
          key: const ValueKey('tts-speak'),
          icon: const Icon(Icons.volume_up),
          onPressed: _speak,
        ),
      ]),
      if (_recents.isNotEmpty)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 4),
          child: Wrap(spacing: 8, children: [
            for (var i = 0; i < _recents.length; i++)
              ActionChip(
                key: ValueKey('tts-recent-$i'),
                label: Text(_recents[i]),
                onPressed: () => _speak(_recents[i]),
              ),
          ]),
        ),
    ]);
  }
}
