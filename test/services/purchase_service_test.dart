import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:bolo/services/purchase_service.dart';

class FakeGateway implements PurchaseGateway {
  final controller = StreamController<List<PurchaseDetails>>();
  final calls = <String>[];
  bool available = true;
  late List<ProductDetails> products = [
    ProductDetails(
        id: supporterProductId,
        title: 'Supporter unlock',
        description: '',
        price: r'$4.99',
        rawPrice: 4.99,
        currencyCode: 'USD'),
  ];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
          productDetails:
              products.where((p) => ids.contains(p.id)).toList(),
          notFoundIDs: []);
  @override
  Future<void> buyNonConsumable(ProductDetails product) async =>
      calls.add('buy:${product.id}');
  @override
  Future<void> restorePurchases() async => calls.add('restore');
  @override
  Future<void> completePurchase(PurchaseDetails purchase) async =>
      calls.add('complete:${purchase.productID}:${purchase.status.name}');
}

PurchaseDetails purchase(String productId, PurchaseStatus status,
    {bool pending = true}) {
  final p = PurchaseDetails(
    purchaseID: 'p1',
    productID: productId,
    verificationData: PurchaseVerificationData(
        localVerificationData: 'x',
        serverVerificationData: 'x',
        source: 'test'),
    transactionDate: null,
    status: status,
  );
  p.pendingCompletePurchase = pending;
  return p;
}

void main() {
  late FakeGateway gateway;
  late List<bool> unlocks; // recorded `restored` flags
  late PurchaseService service;

  setUp(() {
    gateway = FakeGateway();
    unlocks = [];
    service = PurchaseService(gateway,
        onUnlocked: ({required bool restored}) async => unlocks.add(restored));
    service.start();
  });
  tearDown(() {
    service.dispose();
    gateway.controller.close();
  });

  Future<void> emit(PurchaseDetails p) async {
    gateway.controller.add([p]);
    await Future<void>.delayed(Duration.zero); // let the stream deliver
  }

  test('purchased unlocks (restored=false) and completes', () async {
    await emit(purchase(supporterProductId, PurchaseStatus.purchased));
    expect(unlocks, [false]);
    expect(gateway.calls,
        contains('complete:bolo_supporter_unlock:purchased'));
  });

  test('restored unlocks (restored=true) and completes', () async {
    await emit(purchase(supporterProductId, PurchaseStatus.restored));
    expect(unlocks, [true]);
    expect(gateway.calls,
        contains('complete:bolo_supporter_unlock:restored'));
  });

  test('canceled and error never unlock but still complete when pending',
      () async {
    await emit(purchase(supporterProductId, PurchaseStatus.canceled));
    await emit(purchase(supporterProductId, PurchaseStatus.error));
    expect(unlocks, isEmpty);
    expect(
        gateway.calls.where((c) => c.startsWith('complete:')).length, 2);
  });

  test('not-pending purchases are not completed twice', () async {
    await emit(
        purchase(supporterProductId, PurchaseStatus.purchased, pending: false));
    expect(unlocks, [false]); // still unlocks
    expect(gateway.calls.where((c) => c.startsWith('complete:')), isEmpty);
  });

  test('other product ids never unlock but are still completed', () async {
    await emit(purchase('some_other_product', PurchaseStatus.purchased));
    expect(unlocks, isEmpty);
    expect(gateway.calls, contains('complete:some_other_product:purchased'));
  });

  test('buy queries the product and buys it', () async {
    await service.buy();
    expect(gateway.calls, contains('buy:bolo_supporter_unlock'));
  });

  test('buy is a no-op when the store is unavailable or product missing',
      () async {
    gateway.available = false;
    await service.buy();
    gateway.available = true;
    gateway.products = [];
    await service.buy();
    expect(gateway.calls.where((c) => c.startsWith('buy:')), isEmpty);
  });

  test('restore delegates to the gateway', () async {
    await service.restore();
    expect(gateway.calls, contains('restore'));
  });
}
