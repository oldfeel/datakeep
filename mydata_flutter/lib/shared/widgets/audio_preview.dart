import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// 内置音频播放器（media_kit）
class AudioPreview extends StatefulWidget {
  final String filePath;
  final String? title;

  const AudioPreview({
    super.key,
    required this.filePath,
    this.title,
  });

  @override
  State<AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<AudioPreview> {
  late final Player _player = Player();
  String? _error;
  bool _opening = true;
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _seeking = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  bool get _hasDuration => _duration.inMilliseconds > 0;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    }));
    _subs.add(_player.stream.buffering.listen((v) {
      if (mounted) setState(() => _buffering = v);
    }));
    _subs.add(_player.stream.position.listen((v) {
      if (mounted && !_seeking) setState(() => _position = v);
    }));
    _subs.add(_player.stream.duration.listen((v) {
      if (mounted) setState(() => _duration = v);
    }));

    if (!File(widget.filePath).existsSync()) {
      _error = '文件不存在';
      _opening = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFile());
  }

  Future<void> _openFile() async {
    try {
      await _player.open(Media(Uri.file(widget.filePath).toString()));
      await _player.play();
      if (mounted) setState(() => _opening = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _opening = false;
        });
      }
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    final max = _hasDuration ? _duration : target;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > max ? max : target);
    await _player.seek(clamped);
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return '00:00';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _buildError(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wide ? 720 : 420,
              minWidth: 280,
              maxHeight: constraints.maxHeight,
            ),
            child: Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _opening
                    ? const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: _buildArtwork(context, large: true)),
                              const SizedBox(width: 24),
                              Expanded(flex: 2, child: _buildControls(context)),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildArtwork(context, large: false),
                              const SizedBox(height: 20),
                              _buildControls(context),
                            ],
                          ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('播放失败', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildArtwork(BuildContext context, {required bool large}) {
    final theme = Theme.of(context);
    final size = large ? 160.0 : 120.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.music_note_rounded,
            size: size * 0.45,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        if (widget.title != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.title!,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_hasDuration && _buffering)
          const LinearProgressIndicator(minHeight: 4)
        else
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: _hasDuration
                  ? _position.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble()
                  : 0,
              max: _hasDuration ? _duration.inMilliseconds.toDouble() : 1,
              onChangeStart: _hasDuration ? (_) => _seeking = true : null,
              onChanged: _hasDuration
                  ? (v) => setState(() => _position = Duration(milliseconds: v.round()))
                  : null,
              onChangeEnd: _hasDuration
                  ? (v) async {
                      _seeking = false;
                      await _player.seek(Duration(milliseconds: v.round()));
                    }
                  : null,
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_position), style: theme.textTheme.labelMedium),
              Text(
                _hasDuration ? _formatDuration(_duration) : '--:--',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '后退 10 秒',
              iconSize: 28,
              onPressed: _hasDuration ? () => _seekRelative(-10) : null,
              icon: const Icon(Icons.replay_10),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(18),
              ),
              onPressed: () => _player.playOrPause(),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 36,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '前进 10 秒',
              iconSize: 28,
              onPressed: _hasDuration ? () => _seekRelative(10) : null,
              icon: const Icon(Icons.forward_10),
            ),
          ],
        ),
      ],
    );
  }
}
