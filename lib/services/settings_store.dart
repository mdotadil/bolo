import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Parent-scoped app settings. Deliberately a SEPARATE file from board.json:
/// 1. Backups (.bolo) zip board.json + media and must NOT carry consent or
///    entitlement onto another phone (a restore must not flip that phone's
///    privacy choice or grant a purchase that wasn't made there) — so
///    settings.json is excluded from BackupService on purpose.
/// 2. board.json's corrupt-reset path rebuilds the board from defaults; that
///    path must never silently reset a parent's telemetry opt-out.
class Settings {
  final bool telemetryEnabled; // store channel: diagnostics consent
  final bool supporterUnlocked; // store channel: one-time IAP entitlement

  const Settings({
    this.telemetryEnabled = true,
    this.supporterUnlocked = false,
  });

  Settings copyWith({bool? telemetryEnabled, bool? supporterUnlocked}) =>
      Settings(
        telemetryEnabled: telemetryEnabled ?? this.telemetryEnabled,
        supporterUnlocked: supporterUnlocked ?? this.supporterUnlocked,
      );

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
        telemetryEnabled: json['telemetryEnabled'] as bool? ?? true,
        supporterUnlocked: json['supporterUnlocked'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'telemetryEnabled': telemetryEnabled,
        'supporterUnlocked': supporterUnlocked,
      };
}

/// settings.json store with BoardStore's exact durability pattern:
/// tmp+rename atomic writes; corrupt file set aside as .corrupt + defaults.
class SettingsStore {
  SettingsStore(this._dir);
  final Directory _dir;

  File get _file => File('${_dir.path}/settings.json');

  Future<Settings> load() async {
    if (_file.existsSync()) {
      try {
        return Settings.fromJson(
            jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        // Keep the broken file for diagnosis, fall back to defaults.
        try {
          _file.renameSync('${_file.path}.corrupt');
        } catch (_) {}
      }
    }
    return const Settings();
  }

  Future<void> save(Settings settings) async {
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
      tmp.renameSync(_file.path);
    } catch (_) {
      // Persistence must never take down the app; in-memory settings stand.
    }
  }
}

final settingsStoreProvider = Provider<SettingsStore>(
    (ref) => throw UnimplementedError('override in main'));

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

class SettingsNotifier extends AsyncNotifier<Settings> {
  @override
  Future<Settings> build() => ref.read(settingsStoreProvider).load();

  Settings get _settings => state.value ?? const Settings();

  Future<void> _update(Settings next) async {
    state = AsyncData(next);
    await ref.read(settingsStoreProvider).save(next);
  }

  Future<void> setTelemetryEnabled(bool enabled) =>
      _update(_settings.copyWith(telemetryEnabled: enabled));

  Future<void> setSupporterUnlocked(bool unlocked) =>
      _update(_settings.copyWith(supporterUnlocked: unlocked));
}
