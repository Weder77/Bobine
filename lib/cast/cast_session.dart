import 'dart:async';
import 'dart:io';

import 'cast_device.dart';

/// What the remote screen is doing.
enum RemoteState { idle, loading, buffering, playing, paused, ended, error }

/// State of the playback on the device, at [at].
class RemoteStatus {
  RemoteStatus({
    this.state = RemoteState.idle,
    this.position = Duration.zero,
    this.duration,
    this.volume,
    this.error,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final RemoteState state;
  final Duration position;

  /// Length of a film or episode; null for live streams or when unknown.
  final Duration? duration;

  /// 0 to 1, when the device tells it.
  final double? volume;
  final String? error;
  final DateTime at;

  bool get playing => state == RemoteState.playing;

  RemoteStatus copyWith({
    RemoteState? state,
    Duration? position,
    Duration? duration,
    double? volume,
    String? error,
    bool clearError = false,
  }) => RemoteStatus(
    state: state ?? this.state,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    volume: volume ?? this.volume,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  String toString() => 'RemoteStatus($state ${position.inSeconds}/${duration?.inSeconds} s, vol $volume, $error)';
}

/// What the device is asked to open.
class CastMedia {
  const CastMedia({
    required this.url,
    required this.contentType,
    required this.live,
    required this.title,
    this.subtitle,
    this.image,
  });

  final String url;
  final String contentType;
  final bool live;
  final String title;
  final String? subtitle;
  final String? image;
}

class CastException implements Exception {
  CastException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A connection to one device (Chromecast or DLNA renderer).
abstract class CastSession {
  CastDevice get device;

  /// Address of this computer as seen from the device (for the relay).
  InternetAddress? get localAddress;

  /// Status changes the device sends by itself (Chromecast); DLNA is polled.
  Stream<RemoteStatus> get updates;

  Future<void> connect();

  /// MIME type to announce for [url], as this device expects it.
  String contentTypeFor(String url, {required bool live});

  Future<void> load(CastMedia media, {Duration? start});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// [level] from 0 to 1.
  Future<void> setVolume(double level);

  /// Stops the playback on the device.
  Future<void> stop();
  Future<RemoteStatus> poll();

  /// Ends the connection (the device goes back to its home screen).
  Future<void> close();
}
