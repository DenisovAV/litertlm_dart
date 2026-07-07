import 'package:litertlm_dart/litertlm_dart.dart';
import 'package:test/test.dart';

void main() {
  test('declares the targeted native LiteRT-LM version', () {
    expect(targetLiteRtLmVersion, isNotEmpty);
  });
}
