/// Build-time distribution channel.
///
/// sideload (default): the family build. Firebase is NEVER initialized, no
/// IAP is ever constructed, every feature is unlocked, fully offline.
/// store: the Play build. Firebase bootstrap + diagnostics toggle +
/// supporter unlock.
enum AppChannel { sideload, store }

const String _rawChannel =
    String.fromEnvironment('BOLO_CHANNEL', defaultValue: 'sideload');

/// Master gate for the product track. A compile-time const: in sideload
/// builds every `appChannel == AppChannel.store` branch is dead code and is
/// tree-shaken out of the family APK.
///
/// Dart has no const functions, so this expression and [parseChannel] MUST
/// stay textually in sync.
const AppChannel appChannel =
    _rawChannel == 'store' ? AppChannel.store : AppChannel.sideload;

/// Runtime mirror of the [appChannel] const expression, unit-testable for
/// both parse paths (the const itself is fixed by --dart-define at compile
/// time and cannot be varied inside one test binary).
AppChannel parseChannel(String raw) =>
    raw == 'store' ? AppChannel.store : AppChannel.sideload;
