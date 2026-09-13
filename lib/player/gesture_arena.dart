import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

class GestureArena extends StatefulWidget {
  final Widget child;
  final bool isUiLocked;
  final double currentScale;
  final TransformationController transformationController;
  final Duration position;
  final Duration duration;
  final double playbackRate;
  final VoidCallback onTap;
  final Function(double) onZoomUpdate;
  final Function(Duration) onSeekUpdate;
  final Function(Duration) onSeekEnd;
  final Function(double) onBrightnessUpdate;
  final Function(double) onVolumeUpdate;
  final Function(double) onLongPressStart;
  final Function(double) onLongPressMove;
  final VoidCallback onLongPressEnd;
  final VoidCallback onDoubleTapReset;
  final Function(bool isRight) onDoubleTapSeek;
  final Function(String text, IconData icon, {bool isVertical, bool isLeft}) showIndicator;
  final VoidCallback hideIndicator;

  const GestureArena({
    super.key,
    required this.child,
    required this.isUiLocked,
    required this.currentScale,
    required this.transformationController,
    required this.position,
    required this.duration,
    required this.playbackRate,
    required this.onTap,
    required this.onZoomUpdate,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    required this.onBrightnessUpdate,
    required this.onVolumeUpdate,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onDoubleTapReset,
    required this.onDoubleTapSeek,
    required this.showIndicator,
    required this.hideIndicator,
  });

  @override
  State<GestureArena> createState() => _GestureArenaState();
}

class _GestureArenaState extends State<GestureArena> {
  int _pointers = 0;
  bool _isMultiTouch = false;
  bool _isScrubbing = false;
  bool _isLongPressing = false;
  late Duration _scrubStartPosition;
  late Duration _scrubTargetPosition;
  late double _brightness;
  late double _volume;
  late Matrix4 _startMatrix;
  late Offset _startFocalPoint;

  @override
  void initState() {
    super.initState();
    _initDeviceSettings();
  }

  void _initDeviceSettings() {
    Future.microtask(() async {
      try {
        _brightness = await ScreenBrightness().application;
      } catch (_) {
        _brightness = 0.5;
      }
      try {
        _volume = await VolumeController.instance.getVolume();
      } catch (_) {
        _volume = 0.5;
      }
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Listener(
      onPointerDown: (e) => _pointers++,
      onPointerUp: (e) => _pointers = math.max(0, _pointers - 1),
      onPointerCancel: (e) => _pointers = math.max(0, _pointers - 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: () {
          if (widget.isUiLocked) return;
          if (widget.currentScale > 1.05) {
            widget.onDoubleTapReset();
            return;
          }
        },
        onDoubleTapDown: (details) {
          if (widget.isUiLocked) return;
          if (widget.currentScale > 1.05) {
            widget.onDoubleTapReset();
            return;
          }
          final isRight = details.localPosition.dx > screenWidth / 2;
          widget.onDoubleTapSeek(isRight);
        },
        onScaleStart: (details) {
          if (widget.isUiLocked) return;
          _isMultiTouch = details.pointerCount > 1 || _pointers > 1;
          _startMatrix = widget.transformationController.value.clone();
          _startFocalPoint = details.localFocalPoint;
          if (!_isMultiTouch) {
            _isScrubbing = false;
          }
        },
        onScaleUpdate: (details) {
          if (widget.isUiLocked) return;

          if (_isMultiTouch || details.pointerCount > 1) {
            final Offset focalPoint = details.localFocalPoint;
            final double scale = details.scale;
            final Offset focalDelta = focalPoint - _startFocalPoint;

            final Matrix4 m = _startMatrix.clone();
            m.translate(focalDelta.dx, focalDelta.dy, 0.0);
            m.translate(focalPoint.dx, focalPoint.dy, 0.0);
            m.scale(scale, scale, 1.0);
            m.translate(-focalPoint.dx, -focalPoint.dy, 0.0);
            
            widget.transformationController.value = m;
            widget.onZoomUpdate(widget.transformationController.value.getMaxScaleOnAxis());
            
            if (widget.currentScale > 1.01) {
              widget.showIndicator('Zoom: ${widget.currentScale.toStringAsFixed(1)}x', Icons.zoom_in);
            }
            return;
          }

          if (_pointers <= 1) {
            final delta = details.focalPointDelta;
            if (details.scale == 1.0) {
              if (delta.dx.abs() > delta.dy.abs() && !_isScrubbing && delta.dx.abs() > 2) {
                 _isScrubbing = true;
                 _scrubStartPosition = widget.position;
                 _scrubTargetPosition = widget.position;
              }

              if (_isScrubbing) {
                final double totalSeconds = widget.duration.inSeconds.toDouble();
                final double dragDistance = delta.dx / screenWidth;
                final double seekSeconds = dragDistance * (totalSeconds / 4.0);
                
                final targetMs = (_scrubTargetPosition.inMilliseconds + seekSeconds * 1000).toInt();
                _scrubTargetPosition = Duration(milliseconds: targetMs.clamp(0, widget.duration.inMilliseconds));
                
                final diff = _scrubTargetPosition - _scrubStartPosition;
                final sign = diff.inSeconds >= 0 ? '+' : '-';
                final diffStr = _formatDuration(diff.abs());
                widget.showIndicator('[$sign$diffStr] -> ${_formatDuration(_scrubTargetPosition)}', diff.inSeconds >= 0 ? Icons.fast_forward : Icons.fast_rewind);
                widget.onSeekUpdate(_scrubTargetPosition);
              } else if (!_isLongPressing && widget.currentScale <= 1.01) {
                final x = details.focalPoint.dx;
                final dy = -delta.dy / 250.0;
                if (x < screenWidth * 0.35) {
                  _brightness = (_brightness + dy).clamp(0.0, 1.0);
                  ScreenBrightness().setApplicationScreenBrightness(_brightness);
                  widget.showIndicator('${(_brightness * 100).toInt()}%', Icons.brightness_medium, isVertical: true, isLeft: true);
                  widget.onBrightnessUpdate(_brightness);
                } else if (x > screenWidth * 0.65) {
                  _volume = (_volume + dy).clamp(0.0, 1.0);
                  VolumeController.instance.setVolume(_volume);
                  widget.showIndicator('${(_volume * 100).toInt()}%', _volume == 0 ? Icons.volume_off : Icons.volume_up, isVertical: true, isLeft: false);
                  widget.onVolumeUpdate(_volume);
                }
              }
            }
          }
        },
        onScaleEnd: (details) {
          if (_isScrubbing && !_isMultiTouch) {
            widget.onSeekEnd(_scrubTargetPosition);
            _isScrubbing = false;
            widget.hideIndicator();
          }
          _isMultiTouch = false;
        },
        onLongPressStart: (details) {
          if (widget.isUiLocked || _isMultiTouch) return;
          _isLongPressing = true;
          widget.onLongPressStart(widget.playbackRate);
        },
        onLongPressMoveUpdate: (details) {
          if (!_isLongPressing || _isMultiTouch) return;
          final double deltaY = -details.localOffsetFromOrigin.dy;
          final double speedDelta = (deltaY / 25.0) * 0.25;
          double newRate = (2.0 + speedDelta);
          newRate = (newRate * 4).round() / 4.0;
          newRate = newRate.clamp(0.5, 4.0);
          widget.onLongPressMove(newRate);
        },
        onLongPressEnd: (details) {
          if (_isLongPressing) {
            _isLongPressing = false;
            widget.onLongPressEnd();
            widget.hideIndicator();
          }
        },
        onLongPressCancel: () {
          if (_isLongPressing) {
            _isLongPressing = false;
            widget.onLongPressEnd();
            widget.hideIndicator();
          }
        },
        child: widget.child,
      ),
    );
  }
}
