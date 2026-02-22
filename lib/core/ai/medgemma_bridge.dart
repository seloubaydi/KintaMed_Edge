import 'dart:ffi';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// --- FFI TYPEDEFS ---

typedef LoadMedGemmaC    = Pointer<Void> Function(Pointer<Utf8> modelDir);
typedef LoadMedGemmaDart = Pointer<Void> Function(Pointer<Utf8> modelDir);

typedef UnloadMedGemmaC    = Void Function(Pointer<Void> handle);
typedef UnloadMedGemmaDart = void Function(Pointer<Void> handle);

typedef ResetInferenceStateC    = Void Function(Pointer<Void> handle);
typedef ResetInferenceStateDart = void Function(Pointer<Void> handle);

// NEW: tells C++ where to write the log file
typedef SetLogPathC    = Void Function(Pointer<Utf8> path);
typedef SetLogPathDart = void Function(Pointer<Utf8> path);

typedef MedGemmaTokenizeC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> text,
  Pointer<Int64> outTokens,
  Int32 maxTokens,
);
typedef MedGemmaTokenizeDart = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> text,
  Pointer<Int64> outTokens,
  int maxTokens,
);

typedef RunMedGemmaInferenceC = Void Function(
  Pointer<Void> handle,
  Pointer<Uint8> imageBytes,
  Int32 imageLen,
  Pointer<Utf8> prompt,
  Int32 maxTokens,
  Pointer<NativeFunction<TokenCallbackC>> callback,
);
typedef RunMedGemmaInferenceDart = void Function(
  Pointer<Void> handle,
  Pointer<Uint8> imageBytes,
  int imageLen,
  Pointer<Utf8> prompt,
  int maxTokens,
  Pointer<NativeFunction<TokenCallbackC>> callback,
);

typedef TokenCallbackC = Void Function(Pointer<Utf8> textPiece);

// --- HELPER CLASSES ---

class _InferenceParams {
  final int engineAddress;
  final Uint8List? imageBytes;
  final String promptString;
  final SendPort sendPort;
  final String libPath;
  final String logFilePath; // passed into the isolate so it can re-init logging
  final int maxTokens;

  _InferenceParams({
    required this.engineAddress,
    this.imageBytes,
    required this.promptString,
    required this.sendPort,
    required this.libPath,
    required this.logFilePath,
    required this.maxTokens,
  });
}


// --- MAIN CLASS ---

class MedGemmaBridge {
  final DynamicLibrary _lib;
  Pointer<Void>? _engineHandle;
  bool _isInferenceRunning = false;
  final String _logFilePath;

  /// True after an image inference — vision sessions were freed to save RAM.
  /// resetInferenceState() is called automatically before the next image run.
  bool _visionSessionsFreed = false;

  MedGemmaBridge._(this._lib, this._engineHandle, this._logFilePath);

  /// Returns the path to the native log file so you can display or share it.
  String get logFilePath => _logFilePath;

  /// Reads and returns the current log contents (for showing in UI).
  String readLogs() {
    final f = File(_logFilePath);
    if (!f.existsSync()) return '(no logs yet)';
    return f.readAsStringSync();
  }

  /// Factory method — loads the library, sets the log path, then loads the engine.
  static Future<MedGemmaBridge> create(
    String modelPath, {
    void Function(String)? onLog,
  }) async {
    final String libPath = _resolveLibPath();
    final DynamicLibrary lib = _loadLibrary(libPath);

    // ── Set log file path so C++ can write to it ──────────────────────
    final logPath = await _resolveLogPath();
    _initLogPath(lib, logPath);
    onLog?.call('Log file: $logPath');

     // Load engine in background isolate to prevent ANR
    final engineAddress = await Isolate.run(() {
      final isoLib = _loadLibrary(libPath);
      final loadFn = isoLib.lookupFunction<LoadMedGemmaC, LoadMedGemmaDart>('load_medgemma_4bit');
      final modelPathPtr = modelPath.toNativeUtf8();
      final ptr = loadFn(modelPathPtr);
      calloc.free(modelPathPtr);
      return ptr.address;
    });

    if (engineAddress == 0) throw Exception("Failed to initialize MedGemma engine.");

    final enginePtr = Pointer<Void>.fromAddress(engineAddress);

    return MedGemmaBridge._(lib, enginePtr, logPath);
  }

  static void _initLogPath(DynamicLibrary lib, String logPath) {
    try {
      final setLogFn = lib.lookupFunction<SetLogPathC, SetLogPathDart>(
          'set_log_path');
      final pathPtr = logPath.toNativeUtf8();
      setLogFn(pathPtr);
      calloc.free(pathPtr);
    } catch (_) {
      // set_log_path symbol not found — older build, ignore
    }
  }

  static Future<String> _resolveLogPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/app_logs.txt';
  }

  static String _resolveLibPath() {
    if (Platform.isLinux) {
      final exePath = File(Platform.resolvedExecutable).parent.path;
      return '$exePath/lib/libmedgemma_bridge.so';
    } else if (Platform.isAndroid) {
      return 'libmedgemma_bridge.so';
    } else if (Platform.isWindows) {
      // On Windows the DLL is installed next to the .exe (no lib/ subdir)
      final exePath = File(Platform.resolvedExecutable).parent.path;
      return '$exePath\\medgemma_bridge.dll';
    }
    return '';
  }

  static DynamicLibrary _loadLibrary(String path) {
    if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
    if (Platform.isAndroid) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {
        try {
          DynamicLibrary.open('libonnxruntime.so');
          DynamicLibrary.open('libonnxruntime-genai.so');
          return DynamicLibrary.open(path);
        } catch (e) {
          throw Exception('Failed to load native libraries on Android: $e');
        }
      }
    }
    if (Platform.isWindows) {
      // Windows does not use RPATH, so we must load the ONNX Runtime DLLs
      // explicitly before loading the bridge DLL that depends on them.
      try {
        final dir = File(path).parent.path;
        DynamicLibrary.open('$dir\\onnxruntime.dll');
        DynamicLibrary.open('$dir\\onnxruntime-genai.dll');
        return DynamicLibrary.open(path);
      } catch (e) {
        throw Exception('Failed to load native libraries on Windows: $e');
      }
    }
    return DynamicLibrary.open(path);
  }

  void dispose() {
    if (_engineHandle != null) {
      final unload = _lib.lookupFunction<UnloadMedGemmaC, UnloadMedGemmaDart>(
          'unload_medgemma');
      unload(_engineHandle!);
      _engineHandle = null;
    }
  }

  /// Reloads the vision encoder + projection sessions that were destroyed
  /// during the previous inference to free ~430 MB of working RAM.
  /// Must be called between assessments so the next run can process images.
  /// Safe to call even if sessions are still alive (C++ checks before reloading).
  void resetInferenceState() {
    if (_engineHandle == null) return;
    try {
      final resetFn = _lib.lookupFunction<ResetInferenceStateC, ResetInferenceStateDart>(
          'reset_inference_state');
      resetFn(_engineHandle!);
    } catch (e) {
      // Symbol not found in older builds — safe to ignore
      debugPrint('MedGemmaBridge: reset_inference_state not available: $e');
    }
  }

  List<int> tokenize(String text) {
    if (_engineHandle == null) return [];
    final tokenizeFn = _lib.lookupFunction<MedGemmaTokenizeC, MedGemmaTokenizeDart>(
        'medgemma_tokenize');
    final textPtr = text.toNativeUtf8();
    final tokensPtr = calloc<Int64>(2048);
    try {
      final count = tokenizeFn(_engineHandle!, textPtr, tokensPtr, 2048);
      return tokensPtr.asTypedList(count).toList();
    } finally {
      calloc.free(textPtr);
      calloc.free(tokensPtr);
    }
  }

  Stream<String> analyzeStream({
    Uint8List? imageBytes,
    required String promptText,
    int maxTokens = 512,
    double repetitionPenalty = 1.25,
    void Function(String)? onLog,
  }) async* {
    if (_engineHandle == null) return;
    if (_isInferenceRunning) throw Exception('Inference busy');

    // Construct full prompt here
    String fullPrompt = "";

    fullPrompt += "<start_of_turn>user\n";
    if (imageBytes != null && imageBytes.isNotEmpty) {
      fullPrompt += "<image>\n";
    }
    fullPrompt += "$promptText<end_of_turn>\n<start_of_turn>model\n";

    // Auto-restore vision sessions if a previous image run freed them
    if (imageBytes != null && imageBytes.isNotEmpty && _visionSessionsFreed) {
      resetInferenceState();
      _visionSessionsFreed = false;
    }

    _isInferenceRunning = true;
    final receivePort = ReceivePort();

    final params = _InferenceParams(
      engineAddress: _engineHandle!.address,
      imageBytes: imageBytes,
      promptString: fullPrompt.toString(),
      sendPort: receivePort.sendPort,
      libPath: _resolveLibPath(),
      logFilePath: _logFilePath,
      maxTokens: maxTokens,
    );

    try {
      await Isolate.spawn(_inferenceIsolate, params);
      await for (final message in receivePort) {
        if (message == null) break;
        if (message is String) yield message;
      }
    } finally {
      receivePort.close();
      _isInferenceRunning = false;
      // Vision encoder + projection sessions are freed inside C++ after each
      // image inference to reclaim ~430 MB. Flag this so we know to reload them.
      if (imageBytes != null && imageBytes.isNotEmpty) {
        _visionSessionsFreed = true;
      }
    }
  }
}

// --- ISOLATE ---

void _inferenceIsolate(_InferenceParams params) {
  DynamicLibrary lib;
  if (params.libPath.isEmpty || Platform.isIOS || Platform.isMacOS) {
    lib = DynamicLibrary.process();
  } else if (Platform.isWindows) {
    // Isolates don't share loaded libraries from the main isolate, so we must
    // pre-load the ONNX Runtime DLLs again before opening the bridge DLL.
    final dir = File(params.libPath).parent.path;
    DynamicLibrary.open('$dir\\onnxruntime.dll');
    DynamicLibrary.open('$dir\\onnxruntime-genai.dll');
    lib = DynamicLibrary.open(params.libPath);
  } else {
    lib = DynamicLibrary.open(params.libPath);
  }

  // Re-init log path in the isolate (isolates don't share globals with main)
  if (params.logFilePath.isNotEmpty) {
    try {
      final setLogFn =
          lib.lookupFunction<SetLogPathC, SetLogPathDart>('set_log_path');
      final pathPtr = params.logFilePath.toNativeUtf8();
      setLogFn(pathPtr);
      calloc.free(pathPtr);
    } catch (_) {}
  }

  Pointer<Uint8> imgPtr = nullptr;
  int imgLen = 0;

  if (params.imageBytes != null && params.imageBytes!.isNotEmpty) {
    imgLen = params.imageBytes!.length;
    imgPtr = calloc<Uint8>(imgLen);
    imgPtr.asTypedList(imgLen).setAll(0, params.imageBytes!);
  }

  final promptPtr = params.promptString.toNativeUtf8();

  final callback = NativeCallable<TokenCallbackC>.isolateLocal(
    (Pointer<Utf8> textPtr) {
      params.sendPort.send(textPtr.toDartString());
    },
  );

  final maxTokensResult = params.maxTokens;
  
  try {
    final runFn = lib.lookupFunction<RunMedGemmaInferenceC,
        RunMedGemmaInferenceDart>('run_medgemma_inference');
    runFn(
      Pointer.fromAddress(params.engineAddress),
      imgPtr,
      imgLen,
      promptPtr,
      maxTokensResult,
      callback.nativeFunction,
    );
  } finally {
    if (imgPtr != nullptr) calloc.free(imgPtr);
    calloc.free(promptPtr);
    callback.close();
    params.sendPort.send(null);
  }
}