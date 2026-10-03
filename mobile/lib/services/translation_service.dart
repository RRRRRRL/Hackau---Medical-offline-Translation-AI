/// Offline machine translation for FieldTalk.
///
/// Uses MarianMT (ONNX) via the onnxruntime that sherpa-onnx already bundles
/// in the APK (see mt_onnx.dart) — no second onnxruntime, no symbol conflict.
/// Each pair {src}_{tgt} ships an int8-quantized encoder_model.onnx and
/// decoder_model.onnx plus source.spm / target.spm (SentencePiece), a vocab.json
/// (piece<->id), a vid2sid.json (tokenizer-id -> SentencePiece-id for the target)
/// and a config.json (token ids). ru<->zh has no direct model and is translated
/// through an English pivot (ru -> en -> zh), matching the backend.
///
/// IMPORTANT: the exported .spm files use a different ID ordering than the
/// model's vocab.json, so we remap through vocab.json (source) and vid2sid.json
/// (target) when talking to the ONNX model.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../config/languages.dart';
import 'mt_onnx.dart';

/// A loaded {src}_{tgt} translator: engine + tokenizers + id remaps.
class _PairTranslator {
  final MarianMtEngine engine;
  final SentencePieceTokenizer sourceTk;
  final SentencePieceTokenizer targetTk;
  final Map<String, int> _pieceToId; // vocab.json: piece -> tokenizer id
  final Map<String, int> _vidToSid; // vid2sid.json: tokenizer id -> spm id
  final int _bosId;

  _PairTranslator(this.engine, this.sourceTk, this.targetTk, this._pieceToId,
      this._vidToSid, this._bosId);

  String translate(String text) {
    // Source: spm-encode -> remap pieces to tokenizer ids -> append BOS.
    final enc = sourceTk.encode(text, addSpecialTokens: false);
    final srcIds = <int>[];
    for (final piece in enc.tokens) {
      final id = _pieceToId[piece];
      if (id == null) continue;
      srcIds.add(id);
    }
    srcIds.add(_bosId);

    // Greedy decode -> tokenizer-id list.
    final tgtIds = engine.decode(srcIds);

    // Target: tokenizer id -> spm id (vid2sid) -> SentencePiece decode.
    final spmIds = <int>[];
    for (final id in tgtIds) {
      final sid = _vidToSid['$id'];
      if (sid == null) continue; // skip pad/bos/eos/unk (not in spm vocab)
      spmIds.add(sid);
    }
    return targetTk.decode(spmIds);
  }
}

class TranslationService {
  static const String _mtRoot = 'assets/models/mt';
  final Map<String, _PairTranslator> _cache = {};

  /// Translate [text] from [source] to [target] on-device.
  Future<String> translate(
    String text,
    String source,
    String target, {
    bool Function()? unavailable,
  }) async {
    if (text.trim().isEmpty) return '';

    try {
      if (LanguageConfig.isPivot(source, target)) {
        // ru <-> zh via English pivot.
        final en = await _translateDirect(text, source, LanguageConfig.pivotLanguage);
        if (en.trim().isEmpty) return '';
        return await _translateDirect(en, LanguageConfig.pivotLanguage, target);
      }
      return await _translateDirect(text, source, target);
    } catch (e) {
      unavailable?.call();
      rethrow;
    }
  }

  Future<String> _translateDirect(String text, String source, String target) async {
    final key = '${source}_$target';
    final translator = _cache[key] ?? await _loadPair(source, target);
    _cache[key] = translator;
    return translator.translate(text);
  }

  Future<_PairTranslator> _loadPair(String source, String target) async {
    final key = '${source}_$target';
    final dir = '$_mtRoot/$key';
    final encoderBytes = await _assetBytes('$dir/encoder_model.onnx');
    final decoderBytes = await _assetBytes('$dir/decoder_model.onnx');
    final configRaw = await rootBundle.loadString('$dir/config.json');
    final config = jsonDecode(configRaw) as Map<String, dynamic>;

    final sourceTk = SentencePieceTokenizer.fromBytes(
      await _assetBytes('$dir/source.spm'),
    );
    final targetTk = SentencePieceTokenizer.fromBytes(
      await _assetBytes('$dir/target.spm'),
    );

    final vocabRaw = await rootBundle.loadString('$dir/vocab.json');
    final vocab = jsonDecode(vocabRaw) as Map<String, dynamic>;
    final pieceToId = <String, int>{};
    vocab.forEach((piece, id) => pieceToId[piece] = id as int);

    final vidRaw = await rootBundle.loadString('$dir/vid2sid.json');
    final vid2sid = (jsonDecode(vidRaw) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));

    final bos = (config['bos_token_id'] as num?)?.toInt() ?? 0;

    final engine = MarianMtEngine.load(
      encoderBytes: encoderBytes,
      decoderBytes: decoderBytes,
      config: config,
    );
    return _PairTranslator(engine, sourceTk, targetTk, pieceToId, vid2sid, bos);
  }

  Future<Uint8List> _assetBytes(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  }

  void dispose() {
    for (final t in _cache.values) {
      t.engine.dispose();
    }
    _cache.clear();
  }
}