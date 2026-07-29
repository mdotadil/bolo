// PLACEHOLDER — regenerate with `flutterfire configure` once the Firebase
// project (BRA-45) exists. These dummy values compile but must never ship a
// store build: Firebase.initializeApp would fail at runtime. The sideload
// channel never reads this file's values (init is store-only).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ? _ios : _android;

  static const _android = FirebaseOptions(
    apiKey: 'placeholder',
    appId: '1:000000000000:android:placeholder',
    messagingSenderId: '000000000000',
    projectId: 'bolo-placeholder',
  );

  static const _ios = FirebaseOptions(
    apiKey: 'placeholder',
    appId: '1:000000000000:ios:placeholder',
    messagingSenderId: '000000000000',
    projectId: 'bolo-placeholder',
    iosBundleId: 'com.mdotadil.bolo',
  );
}
