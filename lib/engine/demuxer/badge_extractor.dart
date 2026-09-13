import 'dart:async';
import 'package:media_kit/media_kit.dart';
import 'models/technical_badges.dart';

class BadgeExtractor {
  static Future<TechnicalBadges> extractBadges(String filePath) async {
    final Player player = Player();
    final Completer<TechnicalBadges> completer = Completer<TechnicalBadges>();

    StreamSubscription? tracksSubscription;
    Timer? timeoutTimer;

    void cleanup() {
      timeoutTimer?.cancel();
      tracksSubscription?.cancel();
      player.dispose();
    }

    Future<void> finishExtraction() async {
      if (completer.isCompleted) return;

      final state = player.state;
      
      // 1. Resolution
      String res = "SD";
      final w = state.videoParams.w ?? 0;
      if (w >= 3840) {
        res = "4K UHD";
      } else if (w >= 1920) {
        res = "1080p";
      } else if (w >= 1280) {
        res = "720p";
      }

      // 2. Audio Info
      String codec = "Unknown";
      String channels = "Stereo";
      if (state.tracks.audio.isNotEmpty) {
        codec = state.audioParams.format?.toUpperCase() ?? "AAC";
        final channelCount = state.audioParams.channelCount ?? 2;
        if (channelCount >= 8) {
          channels = "7.1";
        } else if (channelCount >= 6) {
          channels = "5.1";
        } else {
          channels = "Stereo";
        }
      }

      // 3. FPS
      double finalFps = 0.0;
      try {
        final dynamic platform = player.platform;
        final dynamic prop = await platform?.getProperty('container-fps');
        if (prop != null) {
          finalFps = double.tryParse(prop.toString()) ?? 0.0;
        }
        if (finalFps == 0.0) {
          final dynamic estimated = await platform?.getProperty('estimated-vf-fps');
          if (estimated != null) {
            finalFps = double.tryParse(estimated.toString()) ?? 0.0;
          }
        }
      } catch (_) {
        finalFps = 0.0;
      }

      String fpsStr = finalFps > 0 ? "${finalFps.round()} FPS" : "Unknown FPS";

      // 4. HDR
      String hdr = "SDR";

      final badges = TechnicalBadges(
        resolutionBadge: res,
        hdrBadge: hdr,
        fpsBadge: fpsStr,
        audioCodecBadge: codec,
        audioChannelsBadge: channels,
        audioTracksCount: state.tracks.audio.length,
        subtitleTracksCount: state.tracks.subtitle.length,
      );

      cleanup();
      completer.complete(badges);
    }

    timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        cleanup();
        completer.complete(TechnicalBadges(
          resolutionBadge: "SD",
          hdrBadge: "SDR",
          fpsBadge: "Unknown FPS",
          audioCodecBadge: "Unknown",
          audioChannelsBadge: "Stereo",
          audioTracksCount: 0,
          subtitleTracksCount: 0,
        ));
      }
    });

    tracksSubscription = player.stream.tracks.listen((tracks) {
      if (tracks.video.isNotEmpty || tracks.audio.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 500), () => finishExtraction());
      }
    });

    try {
      await player.open(Media(filePath), play: false);
    } catch (e) {
      cleanup();
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    return completer.future;
  }
}
