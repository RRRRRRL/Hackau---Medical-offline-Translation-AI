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

    // Greedy decode -> tokenizer-id list. Cap generation high enough to cover
    // the whole chunk (up to ~2x the source length, with a floor) so a long
    // clause is never cut off mid-way.
    final tgtIds = engine.decode(
      srcIds,
      maxLengthOverride: (srcIds.length * 3).clamp(64, 192),
    );

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

  /// Max source tokens per translation chunk. MarianMT quality degrades and it
  /// stops early on very long inputs, so we never translate more than this many
  /// source tokens at once. Text is split into sentences, then over-long
  /// sentences are further split at commas, then at word boundaries, until each
  /// chunk fits the budget. Each chunk is translated independently and the
  /// results joined, so no part of the input is ever dropped.
  static const int _maxChunkTokens = 48;

  /// Translate [text] from [source] to [target] on-device.
  ///
  /// MarianMT is a sentence-level model: when fed multiple sentences at once it
  /// stops after the first clause and drops the rest. So we split the source
  /// into chunks that each fit [_maxChunkTokens], translate each independently
  /// (through the English pivot when needed), strip the leading dash MarianMT
  /// adds, and join them back. This guarantees the whole input is translated.
  Future<String> translate(
    String text,
    String source,
    String target, {
    bool Function()? unavailable,
  }) async {
    if (text.trim().isEmpty) return '';

    try {
      final chunks = _splitChunks(text);
      final out = <String>[];
      for (final chunk in chunks) {
        final translated = LanguageConfig.isPivot(source, target)
            ? await _translateViaPivot(chunk, source, target)
            : await _translateDirect(chunk, source, target);
        final cleaned = _stripLeadingDash(translated);
        if (cleaned.trim().isNotEmpty) out.add(cleaned.trim());
      }
      return out.join(' ');
    } catch (e) {
      unavailable?.call();
      rethrow;
    }
  }

  /// Split [text] into chunks of at most [_maxChunkTokens] source tokens.
  ///
  /// Priority: split at sentence-ending punctuation, then at commas/semicolons,
  /// then at word boundaries. Each returned chunk is trimmed; a trailing
  /// connector (comma) is kept attached to the preceding chunk so the source
  /// reads naturally.
  static List<String> _splitChunks(String text) {
    final sentences = _splitSentences(text);
    final chunks = <String>[];
    for (final sentence in sentences) {
      final sub = _splitOverBudget(sentence);
      chunks.addAll(sub);
    }
    return chunks;
  }

  /// Break [sentence] into pieces each under the token budget, preferring
  /// commas then words. Rough token estimate = word count (Marian spm ~1
  /// token/word for Latin; CJK ~1-2 tokens/char, so we use a conservative
  /// estimate that also counts each CJK char as 1).
  static List<String> _splitOverBudget(String sentence) {
    if (_estimateTokens(sentence) <= _maxChunkTokens) return [sentence];

    // Try comma/semicolon breaks first.
    final commaBreaks = RegExp(r'[,，;；]+').allMatches(sentence).toList();
    if (commaBreaks.isNotEmpty) {
      final parts = <String>[];
      var cursor = 0;
      for (final m in commaBreaks) {
        parts.add(sentence.substring(cursor, m.end).trim());
        cursor = m.end;
      }
      final tail = sentence.substring(cursor).trim();
      if (tail.isNotEmpty) parts.add(tail);
      // Recurse: each part may still be over budget.
      return parts.expand(_splitOverBudget).toList();
    }

    // Fall back to word-boundary splitting.
    final words = sentence.split(RegExp(r'\s+'));
    final parts = <String>[];
    var buf = StringBuffer();
    var bufTokens = 0;
    for (final w in words) {
      if (w.isEmpty) continue;
      final t = _estimateTokens(w);
      if (bufTokens > 0 && bufTokens + t > _maxChunkTokens) {
        parts.add(buf.toString().trim());
        buf = StringBuffer();
        bufTokens = 0;
      }
      buf.write(w);
      buf.write(' ');
      bufTokens += t;
    }
    if (buf.toString().trim().isNotEmpty) parts.add(buf.toString().trim());
    return parts;
  }

  /// Rough token count: each whitespace-delimited word is ~1 token; each CJK
  /// char counts as 1 (conservative for spm which is closer to 1/char).
  static int _estimateTokens(String s) {
    if (s.isEmpty) return 0;
    final words = RegExp(r'\S+').allMatches(s).length;
    final cjkChars = RegExp(
            r'[\u3000-\u303f\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]')
        .allMatches(s)
        .length;
    return words + cjkChars;
  }

  /// ru <-> zh has no direct model: translate through an English pivot.
  Future<String> _translateViaPivot(
      String text, String source, String target) async {
    final en = await _translateDirect(text, source, LanguageConfig.pivotLanguage);
    if (en.trim().isEmpty) return '';
    return _translateDirect(en, LanguageConfig.pivotLanguage, target);
  }

  /// Split text into sentences at `.` `!` `?` (incl. CJK `。！？`).
  ///
  /// Latin/Cyrillic sentences are separated by whitespace; CJK text has no
  /// spaces between sentences, so a sentence-ending punctuation directly
  /// followed by a CJK ideograph is also a boundary. Each sentence keeps its
  /// trailing punctuation (so the source word order survives per-clause
  /// translation) and is trimmed.
  static List<String> _splitSentences(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    // CJK ideograph ranges (Hiragana/Katakana/Han): \\u3040-\\u30ff, \\u3400-\\u4dbf,
    // \\u4e00-\\u9fff, \\uf900-\\ufaff, \\u3000-\\u303f.
    final re = RegExp(
      r'[^.!?。！？]*[.!?。！？]+(?=\s|$|[\u3000-\u303f\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff])',
    );
    final matches = re.allMatches(trimmed).map((m) => m.group(0)!.trim()).toList();
    if (matches.isEmpty) return [trimmed];
    // Append any trailing fragment with no terminal punctuation.
    final lastEnd = re.allMatches(trimmed).last.end;
    final tail = trimmed.substring(lastEnd).trim();
    if (tail.isNotEmpty) matches.add(tail);
    return matches;
  }

  /// MarianMT prefixes each translation with a stray "- " dash; drop it.
  static String _stripLeadingDash(String s) {
    final t = s.trimLeft();
    return t.startsWith('-') ? t.substring(1).trimLeft() : t;
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