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

class FieldColors {
  static const ink = Color(0xFF10110F);
  static const bone = Color(0xFFF4F1E8);
  static const lime = Color(0xFFD8FF3E);
  static const muted = Color(0xFFADAEA8);
  static const surface = Color(0xFF20221E);
  static const danger = Color(0xFFFF7770);
}

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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: FieldColors.ink,
        colorScheme: const ColorScheme.dark(
          primary: FieldColors.lime,
          onPrimary: FieldColors.ink,
          surface: FieldColors.surface,
          onSurface: FieldColors.bone,
          error: FieldColors.danger,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, height: 1.0, letterSpacing: -1.5),
          titleLarge: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, height: 1.15),
          bodyLarge: TextStyle(fontSize: 18, height: 1.35),
          bodyMedium: TextStyle(fontSize: 15, height: 1.4),
          labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2),
        ).apply(bodyColor: FieldColors.bone, displayColor: FieldColors.bone),
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
    final state = _recording ? 'RECORDING' : _busy ? 'PROCESSING LOCALLY'
        : _error != null ? 'ACTION NEEDED' : !_modelsReady ? 'LOADING LOCAL DATA'
        : _original != null ? 'TRANSLATION READY' : 'READY TO RECORD';
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('FieldTalk', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 5),
                const Text('OFFLINE EMERGENCY COMMUNICATION',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                        letterSpacing: 1.2, color: FieldColors.muted)),
              ])),
              const Icon(Icons.graphic_eq, color: FieldColors.lime, size: 30),
            ]),
            const SizedBox(height: 27),
            const _SectionLabel('01  LANGUAGE PAIR'),
            const SizedBox(height: 10),
            _LanguageSelector(source: _source, target: _target,
                enabled: !_recording && !_busy, onChanged: _setPair),
            const SizedBox(height: 20),
            _RecordPanel(state: state, recording: _recording, busy: _busy,
                loading: !_modelsReady,
                onPressed: _busy || !_modelsReady ? null : _toggleRecording),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _Notice(message: _error!.startsWith('Microphone')
                  ? 'Allow microphone access, then try again.'
                  : _error!.startsWith('No audio')
                      ? 'No audio was captured. Try recording again.'
                      : _error!.startsWith('Failed to load')
                          ? 'Local language data could not load. Restart the app.'
                          : 'Please try again. If this continues, restart the app.'),
            ],
            if (_original != null && _translated != null) ...[
              const SizedBox(height: 26),
              const _SectionLabel('02  CONVERSATION'),
              const SizedBox(height: 10),
              _ResultCard(original: _original!, translated: _translated!,
                  info: _info, totalMs: _totalMs, note: _translationNote,
                  onPlay: _audioPath == null || _busy ? null
                      : () => _player.play(DeviceFileSource(_audioPath!))),
            ],
            const SizedBox(height: 28),
            const _SectionLabel('03  QUICK QUESTIONS'),
            const SizedBox(height: 8),
            const Text('Keep the conversation moving.',
                style: TextStyle(color: FieldColors.muted, fontSize: 14)),
            const SizedBox(height: 12),
            ..._questions.asMap().entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: _busy || _recording ? null
                    : () => _setPair(_source, _source == 'en' ? 'ru' : 'en'),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size.fromHeight(58),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  foregroundColor: FieldColors.bone,
                  side: const BorderSide(color: Color(0xFF4A4D44)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                child: Row(children: [
                  Text((entry.key + 1).toString().padLeft(2, '0'),
                      style: const TextStyle(color: FieldColors.lime,
                          fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(width: 14),
                  Expanded(child: Text(entry.value[_source] ?? '',
                      style: const TextStyle(fontSize: 16, height: 1.3))),
                  const Icon(Icons.north_east, size: 18),
                ]),
              ),
            )),
            const SizedBox(height: 12),
            const Text('LOCAL PROCESSING  /  NO CONNECTION REQUIRED',
                textAlign: TextAlign.center,
                style: TextStyle(color: FieldColors.muted, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1)),
          ]),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(color: FieldColors.lime, fontSize: 11,
          fontWeight: FontWeight.w900, letterSpacing: 1.5));
}

class _LanguageSelector extends StatelessWidget {
  final String source;
  final String target;
  final bool enabled;
  final void Function(String, String) onChanged;
  const _LanguageSelector({required this.source, required this.target,
      required this.enabled, required this.onChanged});
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _LanguageTile(label: 'Source', code: source,
        enabled: enabled, onSelected: (v) => onChanged(v, target))),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 7),
      child: IconButton.filled(
        tooltip: 'Swap languages',
        onPressed: enabled ? () => onChanged(target, source) : null,
        icon: const Icon(Icons.swap_horiz, size: 24),
        style: IconButton.styleFrom(backgroundColor: FieldColors.lime,
            foregroundColor: FieldColors.ink, minimumSize: const Size(48, 48)))),
    Expanded(child: _LanguageTile(label: 'Target', code: target,
        enabled: enabled, onSelected: (v) => onChanged(source, v))),
  ]);
}

class _LanguageTile extends StatelessWidget {
  final String label;
  final String code;
  final bool enabled;
  final ValueChanged<String> onSelected;
  const _LanguageTile({required this.label, required this.code,
      required this.enabled, required this.onSelected});
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    enabled: enabled, tooltip: 'Choose $label language',
    onSelected: onSelected,
    itemBuilder: (_) => LanguageConfig.languages.map((language) =>
        PopupMenuItem<String>(value: language,
            child: Text(LanguageConfig.labels[language]!))).toList(),
    child: Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(color: FieldColors.surface,
          border: Border.all(color: const Color(0xFF595C52), width: 1.5),
          borderRadius: BorderRadius.circular(4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: const TextStyle(
            color: FieldColors.muted, fontSize: 10,
            fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(LanguageConfig.labels[code]!,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          const Icon(Icons.expand_more, size: 18, color: FieldColors.lime),
        ]),
      ]),
    ),
  );
}

class _RecordPanel extends StatelessWidget {
  final String state;
  final bool recording;
  final bool busy;
  final bool loading;
  final VoidCallback? onPressed;
  const _RecordPanel({required this.state, required this.recording,
      required this.busy, required this.loading, required this.onPressed});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: FieldColors.surface,
        border: Border.all(color: recording ? FieldColors.lime : const Color(0xFF4A4D44), width: 1.5),
        borderRadius: BorderRadius.circular(4)),
    child: Column(children: [
      Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(
            color: recording ? FieldColors.danger : FieldColors.lime, shape: BoxShape.circle)),
        const SizedBox(width: 9),
        Expanded(child: Text(state, style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.3))),
        const Text('ON DEVICE', style: TextStyle(
            color: FieldColors.muted, fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 20),
      if (busy || loading)
        const Padding(padding: EdgeInsets.symmetric(vertical: 30),
            child: CircularProgressIndicator(color: FieldColors.lime))
      else
        SizedBox(width: 132, height: 132, child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
              backgroundColor: recording ? FieldColors.bone : FieldColors.lime,
              foregroundColor: FieldColors.ink, shape: const CircleBorder()),
          child: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded, size: 54),
        )),
      const SizedBox(height: 16),
      Text(busy ? 'PROCESSING LOCALLY' : loading ? 'LOADING LOCAL DATA'
          : recording ? 'TAP TO STOP' : 'TAP TO RECORD',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
      const SizedBox(height: 6),
      Text(recording ? 'Speak clearly, then stop recording.'
          : busy ? 'Recognizing and translating on this device.'
          : loading ? 'Preparing language resources.' : 'One speaker at a time.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: FieldColors.muted, fontSize: 14)),
    ]),
  );
}

class _Notice extends StatelessWidget {
  final String message;
  const _Notice({required this.message});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: FieldColors.surface,
        border: Border.all(color: FieldColors.danger, width: 1.5),
        borderRadius: BorderRadius.circular(4)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.error_outline, color: FieldColors.danger, size: 24),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('COULD NOT COMPLETE', style: TextStyle(
            color: FieldColors.danger, fontSize: 12,
            fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 5),
        Text(message, style: const TextStyle(fontSize: 15)),
      ])),
    ]),
  );
}

class _ResultCard extends StatelessWidget {
  final String original;
  final String translated;
  final KeyInformation? info;
  final int? totalMs;
  final String note;
  final VoidCallback? onPlay;
  const _ResultCard({required this.original, required this.translated,
      this.info, this.totalMs, this.note = '', this.onPlay});
  @override
  Widget build(BuildContext context) {
    final i = info;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: FieldColors.surface,
            borderRadius: BorderRadius.circular(4)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SectionLabel('ORIGINAL SPEECH'),
          const SizedBox(height: 10),
          SelectableText(original, style: const TextStyle(fontSize: 17, height: 1.4)),
        ]),
      ),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: FieldColors.bone,
            borderRadius: BorderRadius.circular(4)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(note.isEmpty ? 'TRANSLATION' : 'TRANSLATION UNAVAILABLE', style: const TextStyle(color: FieldColors.ink,
              fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
          const SizedBox(height: 12),
          SelectableText(translated, style: const TextStyle(
              color: FieldColors.ink, fontSize: 23,
              fontWeight: FontWeight.w800, height: 1.25)),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Translation could not complete. Check the text before using it.',
                style: TextStyle(color: Color(0xFF8C2823),
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ],
          if (onPlay != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: onPlay,
              icon: const Icon(Icons.volume_up_rounded, size: 23),
              label: Text(note.isEmpty ? 'PLAY TRANSLATION' : 'PLAY AUDIO'),
              style: FilledButton.styleFrom(backgroundColor: FieldColors.ink,
                  foregroundColor: FieldColors.bone,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)))),
          ],
        ]),
      ),
      if (i != null && (i.entities.isNotEmpty || i.negated || i.isQuestion)) ...[
        const SizedBox(height: 14),
        const _SectionLabel('KEY INFORMATION'),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: FieldColors.surface,
              borderRadius: BorderRadius.circular(4)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...i.entities.map((entity) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Text(entity.category.toUpperCase() + '  /  ' + entity.label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
            if (i.negated) const Text('NEGATION DETECTED',
                style: TextStyle(color: FieldColors.lime, fontSize: 12,
                    fontWeight: FontWeight.w800, letterSpacing: 1)),
            if (i.isQuestion) const Padding(padding: EdgeInsets.only(top: 8),
              child: Text('QUESTION DETECTED', style: TextStyle(
                  color: FieldColors.muted, fontSize: 12,
                  fontWeight: FontWeight.w800, letterSpacing: 1))),
          ]),
        ),
      ],
      if (totalMs != null) Padding(padding: const EdgeInsets.only(top: 10),
        child: Text('Completed locally in $totalMs ms',
            style: const TextStyle(color: FieldColors.muted, fontSize: 12))),
    ]);
  }
}
