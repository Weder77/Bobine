import 'dart:async';
import 'dart:math' as math;
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/net.dart';
import '../../core/text.dart';
import '../../core/theme.dart';

/// Downloads images once, keeps them on disk, limits concurrency and
/// remembers failures so broken logos are not requested again and again.
class ImageFetcher {
  ImageFetcher._(this.dir);
  final String dir;

  static ImageFetcher? _instance;
  static ImageFetcher get instance => _instance!;

  static void init(String dir) {
    Directory(dir).createSync(recursive: true);
    _instance = ImageFetcher._(dir);
    unawaited(_instance!._trim());
  }

  /// Hosts of the sources that accept an invalid certificate: their logos
  /// and posters too. Every other image is fetched with its certificate
  /// checked (TMDB's included).
  static Set<String> acceptInvalidFor = const {};

  final HttpClient _client = createHttpClient(acceptFor: (host) => acceptInvalidFor.contains(host))
    ..maxConnectionsPerHost = 4;
  final Map<String, Future<Uint8List>> _inflight = {};
  final Map<String, DateTime> _failed = {};
  final Queue<Completer<void>> _waiting = Queue();
  int _active = 0;
  static const _maxActive = 8;

  Future<Uint8List> fetch(String url) {
    final failedAt = _failed[url];
    if (failedAt != null && DateTime.now().difference(failedAt).inMinutes < 30) {
      return Future.error(StateError('image failed recently'));
    }
    // Note: the whenComplete callback must not return the removed future,
    // otherwise the returned future would wait on itself forever.
    return _inflight.putIfAbsent(
      url,
      () => _load(url).whenComplete(() {
        _inflight.remove(url);
      }),
    );
  }

  /// A picture kept longer is fetched again (a channel changes its logo,
  /// a poster its picture); the old one is used if that fails.
  static const maxAge = Duration(days: 30);

  Future<Uint8List> _load(String url) async {
    final file = File('$dir/${stableHash(url)}');
    Uint8List? stale;
    if (await file.exists()) {
      final kept = await file.readAsBytes();
      if (DateTime.now().difference((await file.stat()).modified) < maxAge) return kept;
      stale = kept;
    }
    if (_active >= _maxActive) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _active++;
    try {
      final res = await openGet(_client, Uri.parse(url), timeout: const Duration(seconds: 15));
      // A picture that stops arriving would otherwise keep its download slot
      // for good, and after a few of them no picture loads any more.
      final guarded = guardBody(res, stall: const Duration(seconds: 20), maxBytes: 8 << 20);
      final bytes = (await guarded.fold(BytesBuilder(copy: false), (b, chunk) => b..add(chunk))).takeBytes();
      // A web page, an error message or an empty answer sent with 200 was
      // kept as a picture, for good.
      if (!looksLikeImage(bytes)) throw StateError('not an image');
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: false);
      await tmp.rename(file.path);
      return bytes;
    } catch (e) {
      if (stale != null) return stale;
      _failed[url] = DateTime.now();
      rethrow;
    } finally {
      _active--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }

  /// Keeps the disk cache under ~400 MB (oldest files removed first).
  Future<void> _trim() async {
    try {
      final files = <(File, FileStat)>[];
      var total = 0;
      await for (final e in Directory(dir).list()) {
        if (e is File) {
          final st = await e.stat();
          files.add((e, st));
          total += st.size;
        }
      }
      const limit = 400 * 1024 * 1024;
      if (total < limit) return;
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final f in files) {
        if (total < limit * 0.8) break;
        total -= f.$2.size;
        await f.$1.delete();
      }
    } catch (_) {}
  }
}

@immutable
class DiskCachedImage extends ImageProvider<DiskCachedImage> {
  const DiskCachedImage(this.url);
  final String url;

  @override
  Future<DiskCachedImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(DiskCachedImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0, debugLabel: url);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await ImageFetcher.instance.fetch(url);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) => other is DiskCachedImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

bool _isHttp(String? url) => url != null && (url.startsWith('http://') || url.startsWith('https://'));

/// Network image decoded at display size (low memory) with a fade-in and a
/// graceful placeholder.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.decodeWidth,
    this.placeholder,
    this.alignment = Alignment.center,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Logical width used to size the decoded bitmap.
  final double? decodeWidth;
  final Widget? placeholder;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final ph = placeholder ?? ColoredBox(color: AppColors.surface2);
    if (!_isHttp(url)) return SizedBox(width: width, height: height, child: ph);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final dw = decodeWidth ?? width;
    // Always decoded at a bounded width: a few hundred KB can announce a
    // picture of billions of pixels, decoded whole when no width was known.
    final provider = ResizeImage(DiskCachedImage(url!), width: math.min(((dw ?? 1920) * dpr).round(), 3840));
    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => SizedBox(width: width, height: height, child: ph),
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            if (frame == null) SizedBox(width: width, height: height, child: ph),
            AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 220), child: child),
          ],
        );
      },
    );
  }
}

/// The first bytes are those of a picture format the app decodes (JPEG,
/// PNG, GIF, WebP, BMP, ICO, AVIF / HEIF).
bool looksLikeImage(List<int> b) {
  if (b.length < 16) return false;
  bool at(int i, List<int> sig) {
    for (var k = 0; k < sig.length; k++) {
      if (b[i + k] != sig[k]) return false;
    }
    return true;
  }

  return at(0, [0xFF, 0xD8, 0xFF]) ||
      at(0, [0x89, 0x50, 0x4E, 0x47]) ||
      at(0, 'GIF8'.codeUnits) ||
      (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) ||
      at(0, 'BM'.codeUnits) ||
      at(0, [0, 0, 1, 0]) ||
      at(4, 'ftyp'.codeUnits);
}
