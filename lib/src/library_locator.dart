import 'dart:io';

import 'package:meta/meta.dart';

/// Strategy for locating the LiteRT-LM native libraries (libLiteRtLm and its
/// companions, incl. the StreamProxy helper).
///
/// Replaces the per-platform hardcoded paths of the original client with an
/// injectable seam:
///
/// * [LibraryLocator.defaultForPlatform] — app builds: Native Assets
///   locations, Apple framework names, Linux RTLD_GLOBAL ordering.
/// * [LibraryLocator.fromDirectory] — CLI/server: a directory with the
///   platform's .so/.dylib/.dll files.
/// * [LibraryLocator.custom] — full control.
class LibraryLocator {
  const LibraryLocator._(this.mainLibraryPath, this.proxyLibraryPath);

  /// Resolution used inside app bundles (Flutter/Native Assets layouts).
  factory LibraryLocator.defaultForPlatform() {
    if (Platform.isIOS) {
      return const LibraryLocator._(
        '@executable_path/Frameworks/LiteRtLm.framework/LiteRtLm',
        '@executable_path/Frameworks/StreamProxy.framework/StreamProxy',
      );
    }
    if (Platform.isMacOS) {
      return const LibraryLocator._(
        'LiteRtLm.framework/LiteRtLm',
        'StreamProxy.framework/StreamProxy',
      );
    }
    if (Platform.isWindows) {
      return const LibraryLocator._('LiteRtLm.dll', 'StreamProxy.dll');
    }
    // Linux + Android: bare sonames resolved via the loader search path
    // (Native Assets RPATH / apk lib dir).
    return const LibraryLocator._('libLiteRtLm.so', 'libStreamProxy.so');
  }

  /// CLI/server resolution: all libraries live in [directory].
  factory LibraryLocator.fromDirectory(String directory) {
    final sep = Platform.pathSeparator;
    final dir = directory.endsWith(sep)
        ? directory.substring(0, directory.length - sep.length)
        : directory;
    if (Platform.isMacOS) {
      return LibraryLocator._(
        '$dir${sep}libLiteRtLm.dylib',
        '$dir${sep}libStreamProxy.dylib',
      );
    }
    if (Platform.isWindows) {
      return LibraryLocator._(
        '$dir${sep}LiteRtLm.dll',
        '$dir${sep}StreamProxy.dll',
      );
    }
    return LibraryLocator._(
      '$dir${sep}libLiteRtLm.so',
      '$dir${sep}libStreamProxy.so',
    );
  }

  /// Explicit paths, no conventions applied.
  const factory LibraryLocator.custom({
    required String mainLibraryPath,
    required String proxyLibraryPath,
  }) = _CustomLocator;

  /// Path/name passed to `DynamicLibrary.open` for libLiteRtLm.
  ///
  /// Internal: the two-library (main + proxy) shape is an implementation
  /// detail of the current native build — consumers pick a strategy via the
  /// factories, never read these directly, so the shape can evolve (fold
  /// StreamProxy in, add a delegate) without breaking the public contract.
  @internal
  final String mainLibraryPath;

  /// Path/name for the StreamProxy helper (RTLD_GLOBAL loads, stderr capture).
  @internal
  final String proxyLibraryPath;
}

class _CustomLocator extends LibraryLocator {
  const _CustomLocator({
    required String mainLibraryPath,
    required String proxyLibraryPath,
  }) : super._(mainLibraryPath, proxyLibraryPath);
}
