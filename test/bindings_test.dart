import 'package:litertlm_dart/bindings.dart';
import 'package:test/test.dart';

void main() {
  test('raw bindings entrypoint exposes the LiteRtLmBindings class', () {
    // Compile-time reference: the low-level API is importable and the
    // generated binding class is present. Loading a real library needs the
    // native prebuilts (exercised by the integration host), not this unit.
    expect(LiteRtLmBindings, isNotNull);
  });
}
