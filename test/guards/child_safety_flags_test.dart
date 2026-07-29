import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest keeps the child-safety flags', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest,
        contains('xmlns:tools="http://schemas.android.com/tools"'));
    expect(manifest, contains('com.google.android.gms.permission.AD_ID'));
    expect(manifest, contains('tools:node="remove"'));
    expect(manifest, contains('google_analytics_adid_collection_enabled'));
    expect(
        manifest,
        contains(
            'google_analytics_default_allow_ad_personalization_signals'));
    expect(manifest, contains('firebase_analytics_collection_enabled'));
    expect(manifest, contains('firebase_crashlytics_collection_enabled'));
  });

  test('iOS Info.plist keeps the child-safety flags', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('FIREBASE_ANALYTICS_COLLECTION_ENABLED'));
    expect(
        plist,
        contains(
            'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS'));
    expect(plist, contains('GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED'));
    expect(plist, contains('FirebaseCrashlyticsCollectionEnabled'));
  });
}
