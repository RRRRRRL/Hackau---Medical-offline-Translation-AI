/// Minimal ONNX Runtime inference via Dart FFI.
///
/// FieldTalk reuses the `libonnxruntime.so` that sherpa-onnx already bundles in
/// the APK, so we do NOT pull in a second copy of onnxruntime (which previously
/// caused the `OrtGetApiBase` native symbol conflict). We load the same library
/// and call its stable C API (`OrtGetApiBase` -> `OrtApiBase::GetApi`) directly.
///
/// Only the small subset of the ONNX Runtime C API that MarianMT needs is
/// exposed here. The `OrtApi` struct layout comes from onnxruntime 1.15.1
/// (see mt_onnx_bindings.dart); the struct is backward-compatible, so the
/// leading fields used here are valid against the newer onnxruntime bundled
/// by sherpa-onnx (1.28.2).
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'mt_onnx_bindings.dart' as bg;

// ONNX Runtime tensor element data types (onnxruntime_c_api.h).
const int _ortTensorElementTypeInt64 = 7; // ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64

// OrtMemoryInfo allocator / memory types.
const int _ortArenaAllocator = 1; // OrtArenaAllocator
const int _ortMemTypeDefault = 0; // OrtMemTypeDefault

// The bindings were generated against ORT_API_VERSION 15 headers; the runtime
// (sherpa's bundled onnxruntime) supports older API versions, and requesting a
// supported version returns a struct whose leading fields match our layout.
const int _ortApiVersion = 14;

/// Loads a MarianMT model (encoder + decoder) and runs greedy translation.
///
/// Tensors are created/released around each Run; the encoder output (a 3D
/// tensor) is kept alive and handed directly to the decoder so its shape is
/// preserved. Everything is CPU-backed.
class MarianMtEngine {
  final ffi.Pointer<bg.OrtApi> _api;
  final ffi.Pointer<bg.OrtEnv> _env;
  final ffi.Pointer<bg.OrtSession> _encoder;
  final ffi.Pointer<bg.OrtSession> _decoder;
  final ffi.Pointer<bg.OrtMemoryInfo> _mem;

  final int _eosId;
  final int _decoderStartId;
  final int _maxLength;
  final int _vocabSize;

  MarianMtEngine._(
    this._api,
    this._env,
    this._encoder,
    this._decoder,
    this._mem,
    this._eosId,
    this._decoderStartId,
    this._maxLength,
    this._vocabSize,
  );

  /// Open the bundled libonnxruntime.so (sherpa's) and create an engine.
  /// [config] supplies token ids (bos/eos/pad/decoder_start/max_length/vocab_size).
  static MarianMtEngine load({
    required Uint8List encoderBytes,
    required Uint8List decoderBytes,
    required Map<String, dynamic> config,
  }) {
    final b = bg.OnnxRuntimeBindings(
      ffi.DynamicLibrary.open('libonnxruntime.so'),
    );
    final apiBase = b.OrtGetApiBase();
    final api = apiBase.ref.GetApi
        .asFunction<ffi.Pointer<bg.OrtApi> Function(int)>()(_ortApiVersion);
    if (api == ffi.nullptr) {
      throw StateError(
          'ONNX Runtime does not support API version $_ortApiVersion');
    }

    final env = _createEnv(b, api);
    final mem = _createCpuMemoryInfo(b, api);
    final encoder = _createSessionFromArray(api, env, encoderBytes);
    final decoder = _createSessionFromArray(api, env, decoderBytes);

    final eos = _int(config, 'eos_token_id', 0);
    final decStart = _int(config, 'decoder_start_token_id', eos);
    final maxLen = _int(config, 'max_length', 512);
    final vocab = _int(config, 'vocab_size', 65001);

    return MarianMtEngine._(
      api,
      env,
      encoder,
      decoder,
      mem,
      eos,
      decStart,
      maxLen,
      vocab,
    );
  }

  /// Greedy-decode [sourceIds] (already tokenized) into a target token-id list.
  ///
  /// Mirrors Hugging Face Marian greedy generation with a repetition penalty so
  /// short models stop at the sentence end instead of looping.
  List<int> decode(
    List<int> sourceIds, {
    double repetitionPenalty = 1.2,
    int maxLengthOverride = 64,
  }) {
    if (sourceIds.isEmpty) return const [];

    final srcLen = sourceIds.length;
    final encIds = Int64List.fromList(sourceIds);
    final encMask = Int64List(srcLen)..fillRange(0, srcLen, 1);

    // --- Encoder pass ---
    final encOut = _run(
      _encoder,
      inputTensors: [
        _makeInt64Tensor(encIds),
        _makeInt64Tensor(encMask),
      ],
      inputNames: ['input_ids', 'attention_mask'],
      outputNames: ['last_hidden_state'],
    );

    final encHiddenTensor = encOut[0];
    try {
      final maxLen = maxLengthOverride > 0 ? maxLengthOverride : _maxLength;
      final decIds = <int>[_decoderStartId];
      final seen = <int>{};

      for (var step = 0; step < maxLen; step++) {
        final decInput = Int64List.fromList(decIds);
        final logits = _run(
          _decoder,
          inputTensors: [
            _makeInt64Tensor(encMask),
            _makeInt64Tensor(decInput),
            _TensorRef.fromValue(encHiddenTensor), // reuse encoder output
          ],
          inputNames: [
            'encoder_attention_mask',
            'input_ids',
            'encoder_hidden_states',
          ],
          outputNames: ['logits'],
        );
        final logitsTensor = logits[0];
        try {
          final lastRow = _readFloatTensor(logitsTensor);
          final vocabOffset = (decIds.length - 1) * _vocabSize;
          var bestTok = 0;
          var bestLogit = double.negativeInfinity;
          for (var v = 0; v < _vocabSize; v++) {
            var score = lastRow[vocabOffset + v].toDouble();
            if (seen.contains(v)) {
              score =
                  score > 0 ? score / repetitionPenalty : score * repetitionPenalty;
            }
            if (score > bestLogit) {
              bestLogit = score;
              bestTok = v;
            }
          }
          if (bestTok == _eosId) break;
          decIds.add(bestTok);
          seen.add(bestTok);
        } finally {
          _releaseValue(_api, logitsTensor);
        }
      }
      return decIds.skip(1).toList();
    } finally {
      _releaseValue(_api, encHiddenTensor);
    }
  }

  void dispose() {
    _releaseSession(_api, _encoder);
    _releaseSession(_api, _decoder);
    _releaseMemoryInfo(_api, _mem);
    _releaseEnv(_api, _env);
  }

  /// Run one model with the given input tensors; returns the output values.
  List<ffi.Pointer<bg.OrtValue>> _run(
    ffi.Pointer<bg.OrtSession> session, {
    required List<_TensorRef> inputTensors,
    required List<String> inputNames,
    required List<String> outputNames,
  }) {
    final inputPtrs = calloc<ffi.Pointer<bg.OrtValue>>(inputTensors.length);
    final inputNamePtrs = _makeCharPtrArray(inputNames);
    final outputNamePtrs = _makeCharPtrArray(outputNames);
    final outputs = calloc<ffi.Pointer<bg.OrtValue>>(outputNames.length);

    try {
      for (var i = 0; i < inputTensors.length; i++) {
        inputPtrs[i] = inputTensors[i].value;
      }

      final status = _api.ref.Run.asFunction<
          bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtSession>,
              ffi.Pointer<bg.OrtRunOptions>,
              ffi.Pointer<ffi.Pointer<ffi.Char>>,
              ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
              int,
              ffi.Pointer<ffi.Pointer<ffi.Char>>,
              int,
              ffi.Pointer<ffi.Pointer<bg.OrtValue>>)>()(
        session,
        ffi.nullptr,
        inputNamePtrs,
        inputPtrs,
        inputTensors.length,
        outputNamePtrs,
        outputNames.length,
        outputs,
      );
      _checkStatus(_api, status);

      return List.generate(outputNames.length, (j) => outputs[j]);
    } finally {
      _freeCharPtrArray(inputNamePtrs, inputNames.length);
      _freeCharPtrArray(outputNamePtrs, outputNames.length);
      calloc.free(inputPtrs);
      calloc.free(outputs);
      // Free the native buffers backing the input tensors now that Run
      // (CPU, synchronous) has finished.
      for (final t in inputTensors) {
        t.free();
      }
    }
  }

  /// Create a 2D int64 tensor of shape [1, values.length].
  _TensorRef _makeInt64Tensor(Int64List values) {
    final shape = calloc<ffi.Int64>(2);
    final data = calloc<ffi.Int64>(values.length);
    for (var i = 0; i < values.length; i++) {
      data[i] = values[i];
    }
    shape[0] = 1;
    shape[1] = values.length;
    final out = calloc<ffi.Pointer<bg.OrtValue>>();
    try {
      final status = _api.ref.CreateTensorWithDataAsOrtValue.asFunction<
          bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtMemoryInfo>,
              ffi.Pointer<ffi.Void>,
              int,
              ffi.Pointer<ffi.Int64>,
              int,
              int,
              ffi.Pointer<ffi.Pointer<bg.OrtValue>>)>()(
        _mem,
        data.cast<ffi.Void>(),
        values.length * 8,
        shape,
        2,
        _ortTensorElementTypeInt64,
        out,
      );
      _checkStatus(_api, status);
      return _TensorRef(out.value, data.cast<ffi.Void>());
    } finally {
      calloc.free(shape);
      calloc.free(out);
    }
  }

  Float32List _readFloatTensor(ffi.Pointer<bg.OrtValue> value) {
    final shapeInfo = calloc<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>();
    final count = calloc<ffi.Size>();
    final dataPtr = calloc<ffi.Pointer<ffi.Void>>();
    try {
      final s1 = _api.ref.GetTensorTypeAndShape.asFunction<
          bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtValue>,
              ffi.Pointer<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>)>()(
        value,
        shapeInfo,
      );
      _checkStatus(_api, s1);
      final s2 = _api.ref.GetTensorShapeElementCount.asFunction<
          bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>,
              ffi.Pointer<ffi.Size>)>()(
        shapeInfo.value,
        count,
      );
      _checkStatus(_api, s2);
      final n = count.value;
      final s3 = _api.ref.GetTensorMutableData.asFunction<
          bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtValue>,
              ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(
        value,
        dataPtr,
      );
      _checkStatus(_api, s3);

      final floats = dataPtr.value.cast<ffi.Float>();
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        out[i] = floats[i];
      }
      return out;
    } finally {
      _releaseTensorTypeAndShapeInfo(_api, shapeInfo.value);
      calloc.free(shapeInfo);
      calloc.free(count);
      calloc.free(dataPtr);
    }
  }
}

// ---- Free functions that wrap the OrtApi function pointers ----

int _int(Map<String, dynamic> map, String key, int fallback) {
  final v = map[key];
  return v is num ? v.toInt() : fallback;
}

/// A tensor handed to a model Run: the OrtValue plus the native buffer that
/// backs its data (freed after Run completes). Outputs borrowed from a Run
/// have a null [data] and are NOT freed here.
class _TensorRef {
  final ffi.Pointer<bg.OrtValue> value;
  final ffi.Pointer<ffi.Void>? data;
  _TensorRef(this.value, this.data);
  _TensorRef.fromValue(ffi.Pointer<bg.OrtValue> value)
      : this(value, ffi.nullptr);

  void free() {
    if (data != ffi.nullptr) calloc.free(data!);
  }
}

ffi.Pointer<bg.OrtEnv> _createEnv(
    bg.OnnxRuntimeBindings b, ffi.Pointer<bg.OrtApi> api) {
  final out = calloc<ffi.Pointer<bg.OrtEnv>>();
  try {
    final logId = 'fieldtalk-mt'.toNativeUtf8();
    final status = api.ref.CreateEnv.asFunction<
        bg.OrtStatusPtr Function(
            int, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Pointer<bg.OrtEnv>>)>()(
      2, // ORT_LOGGING_LEVEL_WARNING
      logId.cast<ffi.Char>(),
      out,
    );
    calloc.free(logId);
    _checkStatus(api, status);
    return out.value;
  } finally {
    calloc.free(out);
  }
}

ffi.Pointer<bg.OrtMemoryInfo> _createCpuMemoryInfo(
  bg.OnnxRuntimeBindings b,
  ffi.Pointer<bg.OrtApi> api,
) {
  final out = calloc<ffi.Pointer<bg.OrtMemoryInfo>>();
  try {
    final status = api.ref.CreateCpuMemoryInfo.asFunction<
        bg.OrtStatusPtr Function(
            int, int, ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>)>()(
      _ortArenaAllocator,
      _ortMemTypeDefault,
      out,
    );
    _checkStatus(api, status);
    return out.value;
  } finally {
    calloc.free(out);
  }
}

ffi.Pointer<bg.OrtSession> _createSessionFromArray(
  ffi.Pointer<bg.OrtApi> api,
  ffi.Pointer<bg.OrtEnv> env,
  Uint8List modelBytes,
) {
  final options = calloc<ffi.Pointer<bg.OrtSessionOptions>>();
  final session = calloc<ffi.Pointer<bg.OrtSession>>();
  try {
    final s1 = api.ref.CreateSessionOptions.asFunction<
        bg.OrtStatusPtr Function(
            ffi.Pointer<ffi.Pointer<bg.OrtSessionOptions>>)>()(options);
    _checkStatus(api, s1);
    final s2 = api.ref.SetIntraOpNumThreads.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)>()(
      options.value,
      4,
    );
    _checkStatus(api, s2);

    // CreateSessionFromArray copies the model bytes internally, so we can use
    // a temporary native buffer and free it right after the call.
    final buf = calloc<ffi.Uint8>(modelBytes.length);
    buf.asTypedList(modelBytes.length).setAll(0, modelBytes);
    try {
      final status = api.ref.CreateSessionFromArray.asFunction<
          bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtEnv>,
              ffi.Pointer<ffi.Void>,
              int,
              ffi.Pointer<bg.OrtSessionOptions>,
              ffi.Pointer<ffi.Pointer<bg.OrtSession>>)>()(
        env,
        buf.cast<ffi.Void>(),
        modelBytes.length,
        options.value,
        session,
      );
      _checkStatus(api, status);
    } finally {
      calloc.free(buf);
    }
    return session.value;
  } finally {
    _releaseSessionOptions(api, options.value);
    calloc.free(options);
    calloc.free(session);
  }
}

ffi.Pointer<ffi.Pointer<ffi.Char>> _makeCharPtrArray(List<String> names) {
  final arr = calloc<ffi.Pointer<ffi.Char>>(names.length);
  for (var i = 0; i < names.length; i++) {
    arr[i] = names[i].toNativeUtf8().cast<ffi.Char>();
  }
  return arr;
}

void _freeCharPtrArray(ffi.Pointer<ffi.Pointer<ffi.Char>> arr, int length) {
  for (var i = 0; i < length; i++) {
    final p = arr[i];
    if (p != ffi.nullptr) calloc.free(p);
  }
  calloc.free(arr);
}

void _checkStatus(ffi.Pointer<bg.OrtApi> api, bg.OrtStatusPtr status) {
  if (status == ffi.nullptr) return;
  final code = api.ref.GetErrorCode
      .asFunction<int Function(bg.OrtStatusPtr)>()(status);
  final msgPtr = api.ref.GetErrorMessage
      .asFunction<ffi.Pointer<ffi.Char> Function(bg.OrtStatusPtr)>()(status);
  final msg = _cStringToString(msgPtr);
  _releaseStatus(api, status);
  throw StateError('ONNX Runtime error ($code): $msg');
}

/// Read a null-terminated C string from [ptr] without relying on the
/// Utf8/Utf16 pointer extensions (which are ambiguous because ffi.Char and
/// ffi.Utf8 are both Int8).
String _cStringToString(ffi.Pointer<ffi.Char> ptr) {
  final buffer = <int>[];
  for (var i = 0;; i++) {
    final c = ptr[i];
    if (c == 0) break;
    buffer.add(c);
  }
  return String.fromCharCodes(buffer);
}

void _releaseStatus(ffi.Pointer<bg.OrtApi> api, bg.OrtStatusPtr status) {
  api.ref.ReleaseStatus.asFunction<void Function(bg.OrtStatusPtr)>()(status);
}
void _releaseEnv(ffi.Pointer<bg.OrtApi> api, ffi.Pointer<bg.OrtEnv> env) {
  api.ref.ReleaseEnv.asFunction<void Function(ffi.Pointer<bg.OrtEnv>)>()(env);
}
void _releaseSession(
    ffi.Pointer<bg.OrtApi> api, ffi.Pointer<bg.OrtSession> session) {
  api.ref.ReleaseSession
      .asFunction<void Function(ffi.Pointer<bg.OrtSession>)>()(session);
}
void _releaseSessionOptions(
    ffi.Pointer<bg.OrtApi> api, ffi.Pointer<bg.OrtSessionOptions> options) {
  if (options == ffi.nullptr) return;
  api.ref.ReleaseSessionOptions
      .asFunction<void Function(ffi.Pointer<bg.OrtSessionOptions>)>()(options);
}
void _releaseValue(ffi.Pointer<bg.OrtApi> api, ffi.Pointer<bg.OrtValue> value) {
  if (value == ffi.nullptr) return;
  api.ref.ReleaseValue
      .asFunction<void Function(ffi.Pointer<bg.OrtValue>)>()(value);
}
void _releaseMemoryInfo(
    ffi.Pointer<bg.OrtApi> api, ffi.Pointer<bg.OrtMemoryInfo> memInfo) {
  api.ref.ReleaseMemoryInfo
      .asFunction<void Function(ffi.Pointer<bg.OrtMemoryInfo>)>()(memInfo);
}
void _releaseTensorTypeAndShapeInfo(
    ffi.Pointer<bg.OrtApi> api, ffi.Pointer<bg.OrtTensorTypeAndShapeInfo> info) {
  if (info == ffi.nullptr) return;
  api.ref.ReleaseTensorTypeAndShapeInfo
      .asFunction<void Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>)>()(
      info);
}