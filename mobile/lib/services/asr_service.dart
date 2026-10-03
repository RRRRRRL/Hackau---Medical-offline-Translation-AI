/// Offline speech-to-text for FieldTalk.
///
/// Uses sherpa-onnx with two recognizers, routed by source language:
///  - Whisper (multilingual) for English and Russian.
///  - Paraformer (trilingual zh/cantonese/en) for Chinese — Paraformer is far
///    more accurate and stable on Mandarin than Whisper tiny, and it handles
///    Chinese speech that mixes English terms (e.g. drug names).
///
/// Model weights are bundled under assets/models/ and copied to a writable
/// directory on first run so the native engine can open them by absolute path.
/// Recognizers are loaded lazily and cached.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

class AsrResult {
  final String text;
  final String language;
  const AsrResult(this.text, this.language);
}

class AsrService {
  OfflineRecognizer? _whisper;
  OfflineRecognizer? _paraformer;
  bool _initialized = false;

  static const String _whisperAssetDir = 'assets/models/whisper';
  static const String _paraformerAssetDir = 'assets/models/paraformer';

  Future<void> _ensureBindings() async {
    if (_initialized) return;
    initBindings();
    _initialized = true;
  }

  /// Load (lazily) the recognizer for [language] and cache it.
  Future<OfflineRecognizer> _recognizer(String language) async {
    await _ensureBindings();
    if (language == 'zh') {
      _paraformer ??= await _loadParaformer();
      return _paraformer!;
    }
    _whisper ??= await _loadWhisper();
    return _whisper!;
  }

  Future<void> load() async {
    await _ensureBindings();
  }

  Future<OfflineRecognizer> _loadWhisper() async {
    final docs = await getApplicationDocumentsDirectory();
    final modelRoot = p.join(docs.path, 'fieldtalk_models', 'whisper');
    final modelDir = Directory(modelRoot);
    if (!modelDir.existsSync()) modelDir.createSync(recursive: true);

    final encoder = await _copyAsset(_whisperAssetDir, 'encoder.int8.onnx', modelDir);
    final decoder = await _copyAsset(_whisperAssetDir, 'decoder.int8.onnx', modelDir);
    final tokens = await _copyAsset(_whisperAssetDir, 'tokens.txt', modelDir);

    final whisper = OfflineWhisperModelConfig(
      encoder: encoder,
      decoder: decoder,
      language: '',
      task: 'transcribe',
      enableTokenTimestamps: false,
    );
    final model = OfflineModelConfig(
      whisper: whisper,
      tokens: tokens,
      modelType: 'whisper',
      numThreads: 4,
      provider: 'cpu',
    );
    return OfflineRecognizer(OfflineRecognizerConfig(model: model));
  }

  Future<OfflineRecognizer> _loadParaformer() async {
    final docs = await getApplicationDocumentsDirectory();
    final modelRoot = p.join(docs.path, 'fieldtalk_models', 'paraformer');
    final modelDir = Directory(modelRoot);
    if (!modelDir.existsSync()) modelDir.createSync(recursive: true);

    final modelPath = await _copyAsset(_paraformerAssetDir, 'model.int8.onnx', modelDir);
    final tokens = await _copyAsset(_paraformerAssetDir, 'tokens.txt', modelDir);

    final paraformer = OfflineParaformerModelConfig(model: modelPath);
    final model = OfflineModelConfig(
      paraformer: paraformer,
      tokens: tokens,
      modelType: 'paraformer',
      numThreads: 4,
      provider: 'cpu',
    );
    return OfflineRecognizer(OfflineRecognizerConfig(model: model));
  }

  Future<String> _copyAsset(
      String assetDir, String name, Directory dest) async {
    final destPath = p.join(dest.path, name);
    if (File(destPath).existsSync()) return destPath;
    final data = await _readAssetBytes('$assetDir/$name');
    await File(destPath).writeAsBytes(data, flush: true);
    return destPath;
  }

  Future<Uint8List> _readAssetBytes(String path) async {
    final byteData = await rootBundle.load(path);
    return byteData.buffer.asUint8List();
  }

  /// Transcribe a WAV file. [language] is 'en', 'ru' or 'zh'.
  Future<AsrResult> transcribeFile(String wavPath, {String? language}) async {
    final recognizer = await _recognizer(language ?? 'en');
    final wave = readWave(wavPath);
    if (wave.samples.isEmpty) {
      throw ArgumentError('Empty or unreadable audio.');
    }
    final stream = recognizer.createStream();
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    recognizer.decode(stream);
    final result = recognizer.getResult(stream);
    stream.free();
    if (result.text.trim().isEmpty) {
      throw ArgumentError('No speech recognized.');
    }
    return AsrResult(
      result.text.trim(),
      result.lang.isNotEmpty ? result.lang : (language ?? 'en'),
    );
  }
}