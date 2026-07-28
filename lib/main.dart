import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'features/board/board_providers.dart';
import 'services/audio_recorder.dart';
import 'services/board_store.dart';
import 'services/recording_player.dart';
import 'services/speech_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  final docsDir = await getApplicationDocumentsDirectory();
  runApp(ProviderScope(
    overrides: [
      boardStoreProvider.overrideWithValue(BoardStore(
        docsDir,
        loadDefault: () =>
            rootBundle.loadString('assets/board/default_board.json'),
      )),
      ttsProvider.overrideWithValue(FlutterTtsAdapter()),
      docsDirProvider.overrideWithValue(docsDir),
      recordingPlayerProvider.overrideWithValue(AudioplayersRecordingPlayer()),
      recorderProvider.overrideWithValue(RecordPackageRecorder()),
    ],
    child: const _LifecycleFlush(child: BoloApp()),
  ));
}

/// Flushes buffered usage taps when the app goes to background.
class _LifecycleFlush extends ConsumerStatefulWidget {
  const _LifecycleFlush({required this.child});
  final Widget child;
  @override
  ConsumerState<_LifecycleFlush> createState() => _LifecycleFlushState();
}

class _LifecycleFlushState extends ConsumerState<_LifecycleFlush> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
        onPause: () => ref.read(usageStoreProvider).flush());
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
