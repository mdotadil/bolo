import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/services/app_channel.dart';

void main() {
  test("'store' parses to AppChannel.store", () {
    expect(parseChannel('store'), AppChannel.store);
  });

  test('anything else parses to sideload (the safe default)', () {
    expect(parseChannel('sideload'), AppChannel.sideload);
    expect(parseChannel(''), AppChannel.sideload);
    expect(parseChannel('STORE'), AppChannel.sideload); // case-sensitive
    expect(parseChannel('play'), AppChannel.sideload);
  });

  test('a build without --dart-define is the sideload family build', () {
    // The normal suite runs without BOLO_CHANNEL, so the const must be
    // sideload here. The store value is proven by Task 21's dedicated
    // `flutter test --dart-define=BOLO_CHANNEL=store` run.
    expect(appChannel, AppChannel.sideload);
  });
}
