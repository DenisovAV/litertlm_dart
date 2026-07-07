import 'package:flutter/material.dart';
import 'package:litertlm_dart/litertlm_dart.dart';

/// Minimal host for the cross-platform integration suite in
/// `integration_test/` — litertlm_dart is pure Dart, but exercising it on
/// iOS/Android (and uniformly on desktop) needs a Flutter process to live in.
/// The UI is a status line only; all verification lives in the tests.
void main() => runApp(const _HostApp());

class _HostApp extends StatelessWidget {
  const _HostApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'litertlm_dart integration host\n'
            'target LiteRT-LM $targetLiteRtLmVersion',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
