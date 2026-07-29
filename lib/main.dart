import 'dart:ui' show PlatformDispatcher;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'features/board/board_providers.dart';
import 'firebase_options.dart';
import 'services/app_channel.dart';
import 'services/audio_recorder.dart';
import 'services/board_store.dart';
import 'services/recording_player.dart';
import 'services/settings_store.dart';
import 'services/speech_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final docsDir = await getApplicationDocumentsDirectory();
  final settingsStore = SettingsStore(docsDir);
  final settings = await settingsStore.load();

  if (appChannel == AppChannel.store) {
    // STORE CHANNEL ONLY. appChannel is a compile-time const, so this whole
    // block is dead code in the sideload family build (tree-shaken): the
    // family build never initializes Firebase and stays fully offline.
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(settings.telemetryEnabled);
    await FirebaseAnalytics.instance
        .setAnalyticsCollectionEnabled(settings.telemetryEnabled);
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

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
      settingsStoreProvider.overrideWithValue(settingsStore),
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
