import 'package:box_flasher/flasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stock fingerprint is set', () {
    expect(stockFingerprint, contains('A95X_R1_RTL'));
  });
}
