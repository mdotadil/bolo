import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_channel.dart';

/// The CLOSED parent-mode event taxonomy. This enum IS the analytics schema:
/// there is no free-text event path, and the only parameter ever sent is a
/// language code. Card labels, recordings, photos, typed text, and child tap
/// contents never leave the phone in any channel.
enum ParentEvent {
  languageChanged,
  customCardAdded,
  recordingCreated,
  morePageConfigured,
  backupCreated,
  backupRestored,
  insightsViewed,
  supporterPurchased,
  supporterRestored,
}

/// Parent-mode-only telemetry. In the sideload channel the default sink is
/// null, making log() a compiled no-op. NOTHING under lib/features/board/
/// may import this file (guard-tested).
class TelemetryService {
  TelemetryService(
      {Future<void> Function(String name, Map<String, String> params)? send})
      : _send = send ??
            (appChannel == AppChannel.store ? _firebaseSend : null);

  final Future<void> Function(String name, Map<String, String> params)? _send;

  static const _names = {
    ParentEvent.languageChanged: 'language_changed',
    ParentEvent.customCardAdded: 'custom_card_added',
    ParentEvent.recordingCreated: 'recording_created',
    ParentEvent.morePageConfigured: 'more_page_configured',
    ParentEvent.backupCreated: 'backup_created',
    ParentEvent.backupRestored: 'backup_restored',
    ParentEvent.insightsViewed: 'insights_viewed',
    ParentEvent.supporterPurchased: 'supporter_purchased',
    ParentEvent.supporterRestored: 'supporter_restored',
  };

  static Future<void> _firebaseSend(
          String name, Map<String, String> params) =>
      FirebaseAnalytics.instance.logEvent(name: name, parameters: params);

  Future<void> log(ParentEvent event,
      {Map<String, String> params = const {}}) async {
    final send = _send;
    if (send == null) return; // sideload: telemetry does not exist
    try {
      await send(_names[event]!, params);
    } catch (_) {
      // Telemetry must never break the app.
    }
  }
}

final telemetryProvider =
    Provider<TelemetryService>((ref) => TelemetryService());
