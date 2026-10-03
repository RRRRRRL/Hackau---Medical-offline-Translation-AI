/// FieldTalk mobile entry point.
///
/// Offline, turn-based medical translation for first responders. Captures a
/// short utterance, runs ASR -> translation -> TTS on-device, and surfaces
/// structured key information extracted from the recognised text.
library;

import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'config/languages.dart';
import 'services/asr_service.dart';
import 'services/nlp_service.dart';
import 'services/translation_service.dart';
import 'services/tts_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FieldTalkApp());
}

class FieldTalkApp extends StatelessWidget {
  const FieldTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldTalk',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B6B4F)),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _asr = AsrService();
  final _tts = TtsService();
  final _translation = TranslationService();
  final _nlp = NlpService();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  String _source = 'en';
  String _target = 'ru';
  bool _recording = false;
  bool _busy = false;
  bool _modelsReady = false;
  String? _error;
  String? _original;
  String? _translated;
  KeyInformation? _info;
  String? _audioPath;
  int? _totalMs;
  String _translationNote = '';
  List<Map<String, String>> _questions = [];

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    try {
      await _nlp.load();
      final raw = await rootBundle.loadString('assets/data/quick_questions.json');
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _questions = list
          .map((e) => {
                'id': e['id'] as String,
                'en': e['en'] as String,
                'ru': e['ru'] as String,
                'zh': e['zh'] as String,
              })
          .toList();
      if (mounted) setState(() => _modelsReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load linguistic data: $e');
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    setState(() {
      _error = null;
      _original = null;
      _translated = null;
      _info = null;
      _audioPath = null;
      _translationNote = '';
    });
    if (await _recorder.hasPermission() == false) {
      setState(() => _error = 'Microphone permission denied.');
      return;
    }
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000),
      path: p.join((await getTemporaryDirectory()).path, 'fieldtalk_input.wav'),
    );
    setState(() => _recording = true);
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() => _recording = false);
    if (path == null) {
      setState(() => _error = 'No audio recorded.');
      return;
    }
    await _process(path);
  }

  Future<void> _process(String wavPath) async {
    setState(() => _busy = true);
    final sw = Stopwatch()..start();
    var translationNote = '';
    try {
      final asr = await _asr.transcribeFile(wavPath, language: _source);
      final info = _nlp.extract(asr.text, _source);
      String translated;
      try {
        translated = await _translation.translate(asr.text, _source, _target);
      } catch (e) {
        translationNote = 'Translation failed: $e';
        translated = asr.text;
      }
      final audioPath = await _tts.synthesize(translated, _target);
      sw.stop();
      if (!mounted) return;
      setState(() {
        _original = asr.text;
        _translated = translated;
        _info = info;
        _audioPath = audioPath;
        _totalMs = sw.elapsedMilliseconds;
        _translationNote = translationNote;
      });
      await _player.play(DeviceFileSource(audioPath));
    } catch (e) {
      if (mounted) setState(() => _error = 'Processing failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setPair(String source, String target) {
    if (source == target) return;
    setState(() {
      _source = source;
      _target = target;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FieldTalk')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Offline medical translation for first responders',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _LanguageSelector(
              source: _source,
              target: _target,
              onChanged: _setPair,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _toggleRecording,
                    icon: Icon(_recording ? Icons.stop : Icons.mic),
                    label: Text(_recording ? 'Stop' : 'Record'),
                  ),
                ),
              ],
            ),
            if (_recording)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Recording… speak clearly, then press Stop.'),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Processing on device…'),
              ),
            if (!_modelsReady)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Loading linguistic data…'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_original != null)
              _ResultCard(
                original: _original!,
                translated: _translated!,
                info: _info,
                totalMs: _totalMs,
                audioPath: _audioPath,
                note: _translationNote,
                onPlay: _audioPath == null
                    ? null
                    : () => _player.play(DeviceFileSource(_audioPath!)),
              ),
            const SizedBox(height: 16),
            Text('Quick questions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _questions.map((q) {
                return ActionChip(
                  label: Text(q[_source]!),
                  onPressed: () {
                    _setPair(_source, _source == 'en' ? 'ru' : 'en');
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  final String source;
  final String target;
  final void Function(String, String) onChanged;
  const _LanguageSelector({
    required this.source,
    required this.target,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: source,
            decoration: const InputDecoration(labelText: 'Source'),
            items: LanguageConfig.languages
                .map((c) => DropdownMenuItem(value: c, child: Text(LanguageConfig.labels[c]!)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v, target);
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward),
        ),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: target,
            decoration: const InputDecoration(labelText: 'Target'),
            items: LanguageConfig.languages
                .map((c) => DropdownMenuItem(value: c, child: Text(LanguageConfig.labels[c]!)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(source, v);
            },
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String original;
  final String translated;
  final KeyInformation? info;
  final int? totalMs;
  final String? audioPath;
  final String note;
  final VoidCallback? onPlay;
  const _ResultCard({
    required this.original,
    required this.translated,
    this.info,
    this.totalMs,
    this.audioPath,
    this.note = '',
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final i = info;
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Original', style: Theme.of(context).textTheme.labelLarge),
            Text(original),
            const SizedBox(height: 8),
            Text('Translation', style: Theme.of(context).textTheme.labelLarge),
            Text(translated),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  note,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            if (onPlay != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.volume_up),
                label: const Text('Play audio'),
              ),
            ],
            if (totalMs != null) ...[
              const SizedBox(height: 8),
              Text('Time: $totalMs ms'),
            ],
            if (i != null && i.categories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Key information', style: Theme.of(context).textTheme.labelLarge),
              Wrap(
                spacing: 6,
                children: i.categories.map((c) => Chip(label: Text(c))).toList(),
              ),
              if (i.negated) const Text('Negated'),
              if (i.isQuestion) const Text('Question'),
            ],
          ],
        ),
      ),
    );
  }
}