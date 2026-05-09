import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const VideoOptimizerApp());
}

class VideoOptimizerApp extends StatelessWidget {
  const VideoOptimizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'StoryFit',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7F2),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF116466),
          brightness: Brightness.light,
        ),
        textTheme: Theme.of(context).textTheme.apply(
              bodyColor: const Color(0xFF202422),
              displayColor: const Color(0xFF202422),
            ),
      ),
      home: const OptimizerScreen(),
    );
  }
}

class EncodePreset {
  const EncodePreset({
    required this.name,
    required this.shortName,
    required this.description,
    required this.bitrate,
    required this.maxRate,
    required this.bufferSize,
    required this.tint,
    required this.icon,
  });

  final String name;
  final String shortName;
  final String description;
  final String bitrate;
  final String maxRate;
  final String bufferSize;
  final Color tint;
  final IconData icon;

  List<String> buildArguments(String inputPath, String outputPath) {
    return [
      '-y',
      '-i',
      inputPath,
      '-vf',
      'scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,fps=30,format=yuv420p',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-profile:v',
      'high',
      '-level',
      '4.1',
      '-b:v',
      bitrate,
      '-maxrate',
      maxRate,
      '-bufsize',
      bufferSize,
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-ar',
      '44100',
      '-movflags',
      '+faststart',
      outputPath,
    ];
  }
}

const _presets = [
  EncodePreset(
    name: 'Instagram Story',
    shortName: 'Instagram',
    description: '1080x1920, 30 fps, H.264, AAC, 8 Mbps',
    bitrate: '8M',
    maxRate: '8M',
    bufferSize: '16M',
    tint: Color(0xFFD94F70),
    icon: Icons.camera_alt_rounded,
  ),
  EncodePreset(
    name: 'WhatsApp Status',
    shortName: 'WhatsApp',
    description: '1080x1920, 30 fps, H.264, AAC, 4 Mbps',
    bitrate: '4M',
    maxRate: '4M',
    bufferSize: '8M',
    tint: Color(0xFF16875A),
    icon: Icons.chat_bubble_rounded,
  ),
];

class OptimizerScreen extends StatefulWidget {
  const OptimizerScreen({super.key});

  @override
  State<OptimizerScreen> createState() => _OptimizerScreenState();
}

class _OptimizerScreenState extends State<OptimizerScreen> {
  final _picker = ImagePicker();
  XFile? _source;
  String? _outputPath;
  String? _error;
  String _status = 'Ready';
  double _progress = 0;
  double? _durationMs;
  int? _sessionId;
  bool _isEncoding = false;
  bool _isSaving = false;

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      _source = picked;
      _outputPath = null;
      _error = null;
      _progress = 0;
      _durationMs = null;
      _status = 'Video selected';
    });

    unawaited(_loadDuration(picked.path));
  }

  Future<void> _loadDuration(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final duration = session.getMediaInformation()?.getDuration();
      final seconds = double.tryParse(duration ?? '');
      if (!mounted || seconds == null) return;
      setState(() => _durationMs = seconds * 1000);
    } catch (_) {
      if (!mounted) return;
      setState(() => _durationMs = null);
    }
  }

  Future<void> _encode(EncodePreset preset) async {
    final source = _source;
    if (source == null || _isEncoding) return;

    final outputPath = await _createOutputPath(preset);
    final completer = Completer<void>();

    setState(() {
      _error = null;
      _outputPath = null;
      _progress = 0.02;
      _status = 'Preparing ${preset.shortName} export';
      _isEncoding = true;
    });

    try {
      final session = await FFmpegKit.executeWithArgumentsAsync(
        preset.buildArguments(source.path, outputPath),
        (session) async {
          final code = await session.getReturnCode();
          if (!mounted) {
            completer.complete();
            return;
          }

          if (ReturnCode.isSuccess(code)) {
            setState(() {
              _outputPath = outputPath;
              _progress = 1;
              _status = '${preset.shortName} video ready';
            });
          } else if (ReturnCode.isCancel(code)) {
            setState(() {
              _progress = 0;
              _status = 'Encoding cancelled';
            });
          } else {
            final logs = await session.getAllLogsAsString();
            setState(() {
              _progress = 0;
              _error = _friendlyError(logs);
              _status = 'Encoding failed';
            });
          }

          completer.complete();
        },
        null,
        (Statistics stats) {
          final duration = _durationMs;
          if (!mounted || duration == null || duration <= 0) return;
          final next = (stats.getTime() / duration).clamp(0.02, 0.98);
          setState(() {
            _progress = next;
            _status = 'Encoding ${preset.shortName} ${(_progress * 100).round()}%';
          });
        },
      );

      _sessionId = session.getSessionId();
      await completer.future;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _progress = 0;
        _error = error.toString();
        _status = 'Encoding failed';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isEncoding = false;
          _sessionId = null;
        });
      }
    }
  }

  Future<String> _createOutputPath(EncodePreset preset) async {
    final directory = await getApplicationDocumentsDirectory();
    final cleanName = preset.shortName.toLowerCase();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${directory.path}/storyfit_${cleanName}_$stamp.mp4';
  }

  Future<void> _cancelEncoding() async {
    final id = _sessionId;
    if (id == null) return;
    await FFmpegKit.cancel(id);
  }

  Future<void> _saveToGallery() async {
    final output = _outputPath;
    if (output == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }
      await Gal.putVideo(output, album: 'StoryFit');
      if (!mounted) return;
      setState(() => _status = 'Saved to gallery');
    } on GalException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.type.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _shareOutput() async {
    final output = _outputPath;
    if (output == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(output, mimeType: 'video/mp4')],
        text: 'Optimized with StoryFit',
      ),
    );
  }

  String _friendlyError(String? logs) {
    final text = logs?.trim();
    if (text == null || text.isEmpty) {
      return 'The encoder could not finish this video. Try a shorter clip or a different source file.';
    }
    return text.length > 320 ? text.substring(text.length - 320) : text;
  }

  @override
  Widget build(BuildContext context) {
    final output = _outputPath;
    final source = _source;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            _Header(status: _status, isEncoding: _isEncoding),
            const SizedBox(height: 18),
            _SourcePanel(
              source: source,
              onPick: _isEncoding ? null : _pickVideo,
              onClear: _isEncoding
                  ? null
                  : () => setState(() {
                        _source = null;
                        _outputPath = null;
                        _error = null;
                        _status = 'Ready';
                        _progress = 0;
                      }),
            ),
            const SizedBox(height: 16),
            _ProgressPanel(
              progress: _progress,
              isEncoding: _isEncoding,
              status: _status,
              onCancel: _cancelEncoding,
            ),
            const SizedBox(height: 16),
            Text('Export preset', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            for (final preset in _presets) ...[
              _PresetButton(
                preset: preset,
                enabled: source != null && !_isEncoding,
                onTap: () => _encode(preset),
              ),
              const SizedBox(height: 10),
            ],
            if (output != null) ...[
              const SizedBox(height: 8),
              _ExportPanel(
                filePath: output,
                onSave: _isSaving ? null : _saveToGallery,
                onShare: _shareOutput,
                isSaving: _isSaving,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _MessagePanel(message: _error!),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status, required this.isEncoding});

  final String status;
  final bool isEncoding;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF116466),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.movie_filter_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'StoryFit',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
              ),
              Text(
                isEncoding ? status : 'Light video optimizer',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64706A),
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SourcePanel extends StatelessWidget {
  const _SourcePanel({
    required this.source,
    required this.onPick,
    required this.onClear,
  });

  final XFile? source;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final name = source == null ? 'No video selected' : _fileName(source!.path);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E5DF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.video_library_rounded, color: Color(0xFF116466)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pick one clip from your phone',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64706A),
                        ),
                  ),
                ],
              ),
            ),
            if (source != null)
              IconButton(
                tooltip: 'Clear',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Pick'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({
    required this.progress,
    required this.isEncoding,
    required this.status,
    required this.onCancel,
  });

  final double progress;
  final bool isEncoding;
  final String status;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1EF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (isEncoding)
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Cancel'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: progress == 0 && isEncoding ? null : progress,
                backgroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.preset,
    required this.enabled,
    required this.onTap,
  });

  final EncodePreset preset;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? preset.tint.withValues(alpha: 0.11) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: enabled ? preset.tint : const Color(0xFFCAD0CB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(preset.icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64706A),
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportPanel extends StatelessWidget {
  const _ExportPanel({
    required this.filePath,
    required this.onSave,
    required this.onShare,
    required this.isSaving,
  });

  final String filePath;
  final VoidCallback? onSave;
  final VoidCallback onShare;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final sizeMb = File(filePath).lengthSync() / (1024 * 1024);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E5DF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF16875A)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Export ready (${max(0.01, sizeMb).toStringAsFixed(1)} MB)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSave,
                    icon: isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt_rounded),
                    label: Text(isSaving ? 'Saving' : 'Save'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFECE7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFC8B8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8D2B18),
              ),
        ),
      ),
    );
  }
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
