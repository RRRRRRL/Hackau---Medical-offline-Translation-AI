/// Offline text-to-speech using sherpa-onnx Piper (VITS model).
///
/// Each language has a bundled voice under assets/models/voices/{lang}/.
/// The VITS config needs the .onnx model, a tokens.txt file and a shared
/// espeak-ng-data directory (for grapheme-to-phoneme conversion). All three
/// voices share the same espeak-ng-data, which is stored once under
/// assets/models/voices/espeak-ng-data/ and copied to a writable directory on
/// first run. The list of espeak files is recorded in espeak_manifest.txt.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

class TtsService {
  final Map<String, OfflineTts> _voices = {};
  bool _initialized = false;

  static const String _voicesAssetRoot = 'assets/models/voices';

  /// Bump this when the bundled voice models/tokens change so the app re-copies
  /// them instead of reusing a stale copy from a previous install.
  static const int _modelVersion = 3;

  Future<void> _ensureBindings() async {
    if (_initialized) return;
    initBindings();
    _initialized = true;
  }

  /// Load a voice for [language] lazily and cache it.
  Future<OfflineTts> _voice(String language) async {
    await _ensureBindings();
    if (_voices.containsKey(language)) return _voices[language]!;

    final docs = await getApplicationDocumentsDirectory();
    final voiceRoot =
        p.join(docs.path, 'fieldtalk_models', 'voices', language);
    final dir = Directory(voiceRoot);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    await _refreshIfStale(dir);

    final model = await _copyAsset('$language/$language.onnx', '$language.onnx', dir);
    final tokens = await _copyAsset('$language/tokens.txt', 'tokens.txt', dir);
    final dataDir = await _copySharedEspeak(docs);

    final vits = OfflineTtsVitsModelConfig(
      model: model,
      lexicon: '',
      tokens: tokens,
      dataDir: dataDir,
    );
    final tts = OfflineTts(OfflineTtsConfig(
      model: OfflineTtsModelConfig(vits: vits, numThreads: 2, provider: 'cpu'),
    ));
    _voices[language] = tts;
    return tts;
  }

  /// If the app's model version changed since the last copy, clear the cached
  /// voice files so the new (correct) models are copied. Prevents reusing a
  /// stale .onnx from a previous build.
  Future<void> _refreshIfStale(Directory dir) async {
    final marker = File(p.join(dir.path, '_version'));
    final current = marker.existsSync() ? marker.readAsStringSync() : '';
    if (current == '$_modelVersion') return;
    // Remove old model/tokens; keep espeak (shared, managed separately).
    for (final f in dir.listSync()) {
      if (f is File && (f.path.endsWith('.onnx') || f.path.endsWith('tokens.txt') || f.path.endsWith('_version'))) {
        f.deleteSync();
      }
    }
    marker.writeAsStringSync('$_modelVersion');
  }

  Future<String> _copyAsset(String assetSubpath, String destName, Directory dest) async {
    final destPath = p.join(dest.path, destName);
    if (File(destPath).existsSync()) return destPath;
    final data = await _readAssetBytes('$_voicesAssetRoot/$assetSubpath');
    await File(destPath).writeAsBytes(data, flush: true);
    return destPath;
  }

  /// Copy the shared espeak-ng-data directory once. Uses the manifest file
  /// (one relative path per line) to enumerate the bundled files.
  Future<String> _copySharedEspeak(Directory docs) async {
    final dataDir = p.join(docs.path, 'fieldtalk_models', 'voices', 'espeak-ng-data');
    final marker = File(p.join(dataDir, '_espeak_ok'));
    if (marker.existsSync()) return dataDir;

    final manifestRaw =
        await rootBundle.loadString('$_voicesAssetRoot/espeak_manifest.txt');
    final entries = manifestRaw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);

    // Copy every manifest entry. Be tolerant: if a single asset fails to load
    // (e.g. not bundled in a particular build) log and continue so one missing
    // file cannot abort the whole espeak-ng-data copy.
    var failed = 0;
    for (final rel in entries) {
      final target = File(p.join(dataDir, rel));
      try {
        target.parent.createSync(recursive: true);
        final data = await _readAssetBytes('$_voicesAssetRoot/espeak-ng-data/$rel');
        await target.writeAsBytes(data, flush: true);
      } catch (e) {
        failed++;
        // Swallow: some files may not be bundled in a given build.
      }
    }
    // Only mark complete if we copied every entry we were asked to.
    if (failed == 0) {
      marker.writeAsStringSync('ok');
    }
    return dataDir;
  }

  Future<Uint8List> _readAssetBytes(String path) async {
    final byteData = await rootBundle.load(path);
    return byteData.buffer.asUint8List();
  }

  /// Synthesize [text] into a WAV file and return its path.
  Future<String> synthesize(String text, String language) async {
    final tts = await _voice(language);
    final audio = tts.generate(text: text, sid: 0, speed: 1.0);
    if (audio.samples.isEmpty) {
      throw StateError('TTS produced no audio.');
    }
    final docs = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docs.path, 'fieldtalk_audio'));
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final outPath = p.join(outDir.path, '${DateTime.now().microsecondsSinceEpoch}.wav');
    writeWave(
      filename: outPath,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    return outPath;
  }
}