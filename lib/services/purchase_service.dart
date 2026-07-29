import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'settings_store.dart';
import 'telemetry_service.dart';

/// The one and only product: a one-time non-consumable supporter unlock.
/// Core communication (cards, speech, languages, recordings, backup) is
/// NEVER gated — the unlock buys the insights PDF export and grandfathered
/// access to future premium extras.
const supporterProductId = 'bolo_supporter_unlock';

/// Thin seam over the in_app_purchase plugin (mirrors the Tts seam): tests
/// fake this; only the adapter below touches the platform.
abstract class PurchaseGateway {
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<bool> isAvailable();
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids);
  Future<void> buyNonConsumable(ProductDetails product);
  Future<void> restorePurchases();
  Future<void> completePurchase(PurchaseDetails purchase);
}

class InAppPurchaseGateway implements PurchaseGateway {
  final InAppPurchase _iap = InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;
  @override
  Future<bool> isAvailable() => _iap.isAvailable();
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) =>
      _iap.queryProductDetails(ids);
  @override
  Future<void> buyNonConsumable(ProductDetails product) => _iap
      .buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
  @override
  Future<void> restorePurchases() => _iap.restorePurchases();
  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);
}

class PurchaseService {
  PurchaseService(this._gateway, {required this.onUnlocked});

  final PurchaseGateway _gateway;

  /// Called on entitlement: restored=false for a fresh purchase, true for a
  /// restore. Persists supporterUnlocked — OFFLINE-FOREVER: once stored in
  /// settings.json it is never re-checked online.
  final Future<void> Function({required bool restored}) onUnlocked;

  StreamSubscription<List<PurchaseDetails>>? _sub;

  void start() {
    _sub ??= _gateway.purchaseStream.listen(_onPurchases);
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      final unlocks = p.productID == supporterProductId &&
          (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored);
      if (unlocks) {
        try {
          await onUnlocked(restored: p.status == PurchaseStatus.restored);
        } catch (_) {
          // Entitlement persistence failure must not stop completePurchase.
        }
      }
      // ALWAYS complete — regardless of status or product. Uncompleted
      // purchases are redelivered by the store forever.
      if (p.pendingCompletePurchase) {
        try {
          await _gateway.completePurchase(p);
        } catch (_) {}
      }
    }
  }

  Future<void> buy() async {
    if (!await _gateway.isAvailable()) return;
    final resp = await _gateway.queryProductDetails({supporterProductId});
    final matches =
        resp.productDetails.where((d) => d.id == supporterProductId);
    if (matches.isEmpty) return;
    await _gateway.buyNonConsumable(matches.first);
  }

  Future<void> restore() => _gateway.restorePurchases();

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

final purchaseGatewayProvider = Provider<PurchaseGateway>(
    (ref) => throw UnimplementedError('override in main (store channel only)'));

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  final service = PurchaseService(
    ref.watch(purchaseGatewayProvider),
    onUnlocked: ({required bool restored}) async {
      // Read BEFORE writing: the store redelivers uncompleted/unacknowledged
      // purchases (failed completePurchase, next-launch replay), and Restore
      // re-delivers every non-consumable the account owns even when already
      // unlocked on this phone. The entitlement write below is idempotent and
      // stays unconditional; only the telemetry log must not double-count.
      //
      // Await the FUTURE, not a synchronous .value read: on a cold boot (a
      // purchase can be delivered before anything else has ever read
      // settingsProvider) .value is null, and falling back to default
      // Settings() would clobber a persisted telemetryEnabled: false when
      // setSupporterUnlocked below writes through _settings (state.value ??
      // const Settings()).
      final settings = await ref.read(settingsProvider.future);
      final alreadyUnlocked = settings.supporterUnlocked;
      await ref.read(settingsProvider.notifier).setSupporterUnlocked(true);
      if (alreadyUnlocked) return;
      await ref.read(telemetryProvider).log(restored
          ? ParentEvent.supporterRestored
          : ParentEvent.supporterPurchased);
    },
  );
  ref.onDispose(service.dispose);
  return service;
});
