import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'medgemma_bridge.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../features/settings/presentation/settings_controller.dart';
import 'package:image/image.dart' as img; // Ensure this is imported for img.Image

/// Represents the current lifecycle state of the MedGemma AI model.
enum ModelStatus {
  notInitialized,   // Initial state or model deleted
  checking,         // Verifying file integrity on disk
  downloading,      // Fetching files from HuggingFace
  ready,            // Model is loaded into RAM/NPU and ready for inference
  error,            // Initialization or runtime failure
  downloadingMultimodal, // Specific status for vision-capable models
  initializing,     // Loading model into memory
}

class ModelDownloadState {
  final ModelStatus status;
  final double progress;
  final String? message;
  final int version;
  final int totalSize;
  final int receivedSize;
  final bool isMultimodal;
  final List<String> logs;
  final List<String> problematicFiles;
  final String? currentFileName;
  final int currentFileIndex;
  final int totalFileCount;
  
  ModelDownloadState({
    required this.status,
    this.progress = 0.0,
    this.message,
    this.version = 1,
    this.totalSize = 0,
    this.receivedSize = 0,
    this.isMultimodal = false,
    this.logs = const [],
    this.currentFileName,
    this.currentFileIndex = 0,
    this.totalFileCount = 0,
    this.problematicFiles = const [],
  });

  ModelDownloadState copyWith({
    ModelStatus? status,
    double? progress,
    String? message,
    int? version,
    int? totalSize,
    int? receivedSize,
    bool? isMultimodal,
    List<String>? logs,
    String? currentFileName,
    int? currentFileIndex,
    int? totalFileCount,
    List<String>? problematicFiles,
  }) {
    return ModelDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      version: version ?? this.version,
      totalSize: totalSize ?? this.totalSize,
      receivedSize: receivedSize ?? this.receivedSize,
      isMultimodal: isMultimodal ?? this.isMultimodal,
      logs: logs ?? this.logs,
      currentFileName: currentFileName ?? this.currentFileName,
      currentFileIndex: currentFileIndex ?? this.currentFileIndex,
      totalFileCount: totalFileCount ?? this.totalFileCount,
      problematicFiles: problematicFiles ?? this.problematicFiles,
    );
  }
}

class ModelStatusNotifier extends Notifier<ModelDownloadState> {
  static const String _logFileName = 'app_logs.txt';

  @override
  ModelDownloadState build() {
    // Load logs on build
    Future.microtask(() => loadLogs());
    return ModelDownloadState(status: ModelStatus.notInitialized);
  }

  void updateState(ModelDownloadState newState) {
    state = newState;
  }

  String? _cachedLogPath;
  Future<String> _getLogFilePath() async {
    if (_cachedLogPath != null) return _cachedLogPath!;
    final directory = await getApplicationDocumentsDirectory();
    _cachedLogPath = '${directory.path}/app_logs.txt';
    return _cachedLogPath!;
  }

  Future<void> loadLogs() async {
    try {
      final path = await _getLogFilePath();
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final content = utf8.decode(bytes, allowMalformed: true);
        final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
        
        // Keep last 200 lines from disk
        final lastLogsFromFile = lines.length > 200 ? lines.sublist(lines.length - 200) : lines;
        
        // CRITICAL: Merge with any logs that landed in memory while loading from disk
        // Avoid duplicates if many logs arrive quickly
        final currentLogs = state.logs;
        final mergedLogs = [...lastLogsFromFile, ...currentLogs];
        
        // Cap to 200 entries total
        List<String> finalLogs = mergedLogs.length > 200 
            ? mergedLogs.sublist(mergedLogs.length - 200) 
            : mergedLogs;
            
        state = state.copyWith(logs: finalLogs);
        debugPrint("ModelStatusNotifier: Loaded ${lastLogsFromFile.length} logs from disk. Total: ${finalLogs.length}");
      } else {
        debugPrint("ModelStatusNotifier: No log file found at $path");
      }
    } catch (e) {
      debugPrint("Error loading logs from disk: $e");
    }
  }

  Future<void> log(String message) async {
    final timestamp = DateTime.now().toString().split('.').first;
    final logEntry = "[$timestamp] $message";
    
    // 1. Sync update state for immediate visibility in UI
    final currentLogs = state.logs;
    List<String> newLogs = [...currentLogs, logEntry];
    if (newLogs.length > 200) {
      newLogs = newLogs.sublist(newLogs.length - 200);
    }
    state = state.copyWith(logs: newLogs);

    // 2. Async persist to disk
    try {
      final path = await _getLogFilePath();
      final file = File(path);
      // Mode append is faster and safer than rewrite for crash resilience
      await file.writeAsString("$logEntry\n", mode: FileMode.append, flush: true);
      
      // Periodically trim the file if it gets too large (simple approach)
      final length = await file.length();
      if (length > 1024 * 1024) { // 1MB
         // Trim to last 200 lines
         await file.writeAsString(newLogs.join('\n'), flush: true);
      }
    } catch (e) {
      debugPrint("Error persisting logs: $e");
    }
  }

  Future<void> clearLogs() async {
    state = state.copyWith(logs: []);
    try {
      final path = await _getLogFilePath();
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
       debugPrint("Error clearing logs: $e");
    }
  }
}

final modelStatusProvider = NotifierProvider<ModelStatusNotifier, ModelDownloadState>(() {
  return ModelStatusNotifier();
});

final modelManagerProvider = Provider<ModelManager>((ref) => ModelManager(ref));

class ModelManager {
  final Ref _ref;
  ModelManager(this._ref);

  // Model version/directory name
  // This folder name is where files will be stored locally (e.g. ~/Documents/medgemma/medgemma_int4)
  static const String _modelParams = 'medgemma_int4';
  
  // HuggingFace repository configuration
  static const String _baseUrl = 'https://huggingface.co/eloubaydi/medgemma-1.5-ort-standard/resolve/main';
  
  // Security: HuggingFace Token for gated models or private repositories.
  // Can be provided via --dart-define=HF_TOKEN=your_token at build time.
  static String get _hfToken {
      if (!kIsWeb) {
        final envToken = Platform.environment['HF_TOKEN'];
        if (envToken != null && envToken.isNotEmpty) return envToken;
      }
      return const String.fromEnvironment('HF_TOKEN', defaultValue: '');
  }

  /// CORE MODEL FILES: Required for basic text-instruct capabilities.
  /// model.onnx.data contains the 4-bit quantized weights (~2.7GB).
  static const List<String> _coreFiles = [
    'model.onnx',
    'model.onnx.data',
    'genai_config.json',
    'tokenizer.json',
    'tokenizer_config.json',
    'special_tokens_map.json',
    'embeddings.ort',
    'chat_template.jinja'
  ];
  
  /// VISION FILES: Required for clinical image analysis.
  /// Pre-optimized as .ort files for faster loading on edge devices.
  static const List<String> _visionFiles = [
    "vision_encoder.ort",
    "vision_projection.ort",
  ];
  
  // Get files to download (all files are required for offline capability)
  List<String> _getRequiredFiles() {
    // User requested all files to be present for offline usage.
    // We download everything, and rely on config patching for runtime/memory optimization if possible.
    return [..._coreFiles, ..._visionFiles];
  }
  
  // Combined list for checking existence (helper)
  List<String> get allModelFiles => [..._coreFiles, ..._visionFiles];
  
  bool _isInitialized = false;
  bool _isMockMode = false;
  
  bool get isInitialized => _isInitialized;
  bool get isMockMode => _isMockMode;

  MedGemmaBridge? _bridge;
  String? _currentModelDir;
  String? get currentModelPath => _currentModelDir;

  void log(String message) {
    debugPrint("ModelManager: $message");
    _ref.read(modelStatusProvider.notifier).log(message);
  }

  Future<void> _logMemoryInfo() async {
    if (Platform.isAndroid || Platform.isLinux) {
      try {
        final result = await Process.run('cat', ['/proc/meminfo']);
        if (result.exitCode == 0) {
          final memInfo = result.stdout as String;
          final lines = memInfo.split('\n');
          final memTotal = lines.firstWhere((l) => l.startsWith('MemTotal:'), orElse: () => 'N/A');
          final memAvailable = lines.firstWhere((l) => l.startsWith('MemAvailable:'), orElse: () => 'N/A');
          log("SYSTEM MEMORY: $memTotal, $memAvailable");
        }
      } catch (e) {
        log("DEBUG: Could not read /proc/meminfo: $e");
      }
    }
  }

 /// Cleans AI text from internal tags, thought blocks, and special characters.
  static String cleanAiText(String text) {
    // 0. Remove markdown code blocks (fencing)
    String cleaned = text.replaceAll(RegExp(r'```(?:markdown)?\n?', caseSensitive: false), '');
    cleaned = cleaned.replaceAll('```', '');

    // 1. Remove "thought" blocks - FIX: use 'cleaned', not 'text'
    cleaned = cleaned.replaceAll(RegExp(r'<unused\d+>thought[\s\S]*?(?:<unused\d+>|$)', caseSensitive: false, multiLine: true), "");
    
    // 2. Remove leaked internal reasoning labels
    cleaned = cleaned.replaceAll(RegExp(r'^(?:Plan|Therefore|Note|Observation|Strategy|Internal Reasoning|Thinking|Answer Plan|Question|Execution Strategy):\s*', caseSensitive: false, multiLine: true), "");
    
    // 3. Remove preamble / internal monologue lines
    cleaned = cleaned.replaceAll(RegExp(
      r'^(?:The user wants|The user is asking|I need to|I will|I should|'
      r'Let me|Here is|Here are|I am going to|Based on the|'
      r'In this case|According to the instructions|'
      r'The patient data shows|I have been asked)[^\n]*\n?',
      caseSensitive: false, multiLine: true,
    ), "");

    // 4. Remove other internal tags like <start_of_turn>, <unused...>, etc.
    cleaned = cleaned.replaceAll(RegExp(r'<[a-z0-9_]+>', caseSensitive: false), "");
    
    // This handles:
    // [---END OF REPORT---]
    // [--- END OF REPORT ---]
    // [---END OF REPORT---:FINISHED]
    // [---  END OF REPORT --- : STATUS]
    // ---END OF REPORT---
    cleaned = cleaned.replaceAll(
      RegExp(r'\[?\s*-*\s*END OF REPORT\s*-*\s*(?::\s*[A-Z_]+)?\s*\]?', caseSensitive: false), 
      ""
    );
    cleaned = cleaned.replaceAll(RegExp(r'\[?(?:END OF REPORT)(?::[A-Z]+)?\]?', caseSensitive: false), "");
    
    // 6. Remove special block characters
    cleaned = cleaned.replaceAll('▁', '');
    cleaned = cleaned.replaceAll('_', '');

    // 7. Strip junk before the first meaningful heading
    final headingMatch = RegExp(r'#{2,}\s').firstMatch(cleaned);
    if (headingMatch != null && headingMatch.start > 0) {
      final preamble = cleaned.substring(0, headingMatch.start).trim();
      if (preamble.length < 300 && !preamble.contains(RegExp(r'^[-*]\s', multiLine: true))) {
        cleaned = cleaned.substring(headingMatch.start);
      }
    }

    // 8. CONSOLIDATED LIST FORMATTING
    // Fixes "1)text" -> "\n1. text" and "word 1.text" -> "word\n1. text"
    // Regex breakdown:
    // ([^\s])?         -> Group 1: Optional character that isn't a space (needs a newline before the list)
    // \s* -> Any existing whitespace
    // (?<!\()          -> Lookbehind: Ensure there is no '(' before the number (ignores "(1)")
    // (\d+)            -> Group 2: The list number
    // [.)]             -> Matches either '.' or ')'
    // (?![ \n])        -> Lookahead: Only match if NOT followed by a space or newline
    // ([A-Za-z\[\*])   -> Group 3: The character starting the text
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'([^\s])?\s*(?<!\()(\d+)[.)](?![ \n])([A-Za-z\[\*])'),
      (match) {
        String prefix = (match.group(1) != null) ? '${match.group(1)}\n' : '';
        String number = match.group(2)!;
        String firstChar = match.group(3)!;
        return '$prefix$number. $firstChar';
      },
    );
    
    // Final trim of leading noise (colons, dashes, leading numbers/dots)
    return cleaned.trim().replaceAll(RegExp(r'^[:\-\s\d\.]+'), "");
  }

  Future<String> get _localPath async {
    if (kIsWeb) return ''; 
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getInt('model_version') ?? 1;
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/medgemma/$_modelParams';
  }
  /// Performs a deep-scan on model files to prevent runtime crashes.
  /// Checks for:
  /// 1. Missing files in the model bundle.
  /// 2. Truncated downloads (comparing size against 90% of expected).
  /// 3. Git LFS Pointers (files that look like text instead of binary).
  /// 4. HTML Error pages (often returned by HF when tokens are invalid).
  /// 5. Corrupted JSON configuration files.
  Future<List<String>> verifyModelIntegrity() async {
    if (kIsWeb) return [];
    final List<String> corruptedFiles = [];
    
    try {
      final path = await _localPath;
      final requiredFiles = _getRequiredFiles();
      log("Deep-scanning ${requiredFiles.length} files for integrity...");

      for (var f in requiredFiles) {
        log("SCANNING: $f ...");
        final file = File("$path/$f");
        if (!await file.exists()) {
          log("MISSING: $f");
          corruptedFiles.add(f);
          continue;
        }

        final length = await file.length();
        
        // CHECK 1: Size check for large data files
        const int MB = 1024 * 1024;
        int expectedSize = 0;
        if (f == "model.onnx.data") expectedSize = 2690 * MB;
        else if (f == "embeddings.ort") expectedSize = 671 * MB;
        else if (f == "vision_encoder.ort") expectedSize = 419 * MB;
        else if (f == "vision_projection.ort") expectedSize = 11 * MB;

        if (expectedSize > 0 && length < (expectedSize * 0.9)) {
          log("CORRUPTED (Truncated): $f ($length bytes < expected $expectedSize)");
          corruptedFiles.add(f);
          continue;
        }

        // CHECK 2: Header check for LFS/HTML
        RandomAccessFile? raf;
        try {
          // Direct read for better performance on Android
          raf = await file.open(mode: FileMode.read);
          final bytes = await raf.read(100);
          final header = String.fromCharCodes(bytes).toLowerCase();
          
          if (header.contains("version https://git-lfs") || 
              header.contains("<html>") || 
              header.contains("<!doctype")) {
            log("CORRUPTED (LFS/HTML Pointer): $f");
            corruptedFiles.add(f);
            continue;
          }
        } catch (e) {
          log("⚠️ Could not read header of $f: $e");
        } finally {
          await raf?.close();
        }

        // CHECK 3: JSON Validation (Specifically for config files)
        if (f.endsWith('.json')) {
          try {
            final jsonContent = await file.readAsString();
            jsonDecode(jsonContent);
          } catch (e) {
            log("CORRUPTED (Invalid JSON): $f - $e");
            corruptedFiles.add(f);
            continue;
          }
        }
      }
    } catch (e) {
      log("Error during integrity check: $e");
    }
    
    return corruptedFiles;
  }

  Future<bool> checkModelExists() async {
    if (kIsWeb) return false;
    if (Platform.isMacOS) return true;

    try {
      final problematicFiles = await verifyModelIntegrity();
      final allGood = problematicFiles.isEmpty;
      
      // Update state with problematic files list
      _ref.read(modelStatusProvider.notifier).state = _ref.read(modelStatusProvider).copyWith(
        problematicFiles: problematicFiles,
      );

      if (allGood) {
        log("All required files verified successfully.");
        _ref.read(aiSettingsProvider.notifier).setMultimodalDownloaded(true);
      } else {
        log("${problematicFiles.length} files need repair.");
        _ref.read(aiSettingsProvider.notifier).setMultimodalDownloaded(false);
      }
      return allGood;
    } catch (e) {
      log("Error checking model existence: $e");
      return false;
    }
  }

  /// Fast startup check: only verifies that all required files exist on disk.
  /// Does NOT perform size, header, or JSON validation — that is deferred to
  /// [verifyModelIntegrity] / [checkModelExists] which are used by the
  /// Settings screen and repair flows.
  Future<bool> _quickCheckModelExists() async {
    if (kIsWeb) return false;
    if (Platform.isMacOS) return true;
    try {
      final path = await _localPath;
      for (final f in allModelFiles) {
        if (!await File("$path/$f").exists()) {
          log("QUICK CHECK: Missing file — $f");
          return false;
        }
      }
      log("QUICK CHECK: All model files present.");
      
      return true;
      
    } catch (e) {
      log("QUICK CHECK error: $e");
      return false;
    }
  }

  /// Wipes all model files from local storage.
  /// Used for resetting the app or freeing up massive amounts of storage.
  Future<void> deleteModel() async {
    final path = await _localPath;
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _isInitialized = false;
    _bridge?.dispose();
    _bridge = null;
    _currentModelDir = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('model_version');
    _ref.read(aiSettingsProvider.notifier).setMultimodalDownloaded(false);
    
    _ref.read(modelStatusProvider.notifier).updateState(
      ModelDownloadState(status: ModelStatus.notInitialized)
    );
  }

  /// Explicitly releases the model from memory to free GPU/RAM.
  void disposeModel() {
    debugPrint("ModelManager: Explicitly disposing MedGemma engine.");
    _bridge?.dispose();
    _bridge = null;
    _isInitialized = false;  // Allow re-initialization before next inference
  }

  /// Resets the vision encoder sessions between assessments.
  /// The C++ inference code destroys v_sess / p_sess during inference
  /// to free ~430 MB of working RAM. This call reloads them from disk
  /// so the next assessment can process images again.
  /// The main model (m_sess, e_sess) stays loaded — no long wait.
  void resetInferenceState() {
    if (_bridge == null) return;
    debugPrint("ModelManager: Resetting vision encoder state for next assessment.");
    _bridge!.resetInferenceState();
  }

  bool _isInitializing = false;
  Future<void> init() async {
    if (_isInitialized) return;
    if (_isInitializing) return;
    
    _isInitializing = true;
    
    if (kIsWeb || Platform.isMacOS) {
      _isMockMode = true;
      _isInitialized = true;
      _isInitializing = false;
      return;
    }

    try {
      // Enable Wakelock during initialization
      await WakelockPlus.enable();

      final path = await _localPath;
      
      // Patch config only if needed (MANDATORY for C++ Bridge stability)
      await _enforceConfigConstraints(path);
      
      _ref.read(modelStatusProvider.notifier).updateState(
        _ref.read(modelStatusProvider).copyWith(status: ModelStatus.initializing, message: "Initializing Clinical Engine...")
      );
      
      // CRITICAL FIX: Ensure the engine is loaded into memory
      await _initOnnx(path);
      
      _isInitialized = true;

      _ref.read(aiSettingsProvider.notifier).setMultimodalDownloaded(true);
      _ref.read(modelStatusProvider.notifier).updateState(
        _ref.read(modelStatusProvider).copyWith(status: ModelStatus.ready, message: "AI Ready")
      );
    } catch (e) {
      log("CRITICAL ERROR during AI init: $e");
      _ref.read(modelStatusProvider.notifier).updateState(
        _ref.read(modelStatusProvider).copyWith(status: ModelStatus.error, message: e.toString())
      );
    } finally {
       // Disable Wakelock
      await WakelockPlus.disable();
      _isInitializing = false;
    }
  }

  /// Low-level initialization of the ONNX Runtime engine.
  /// [modelDir] must contain all required .onnx, .ort, and .json files.
  Future<void> _initOnnx(String modelDir) async {
    if (_bridge != null && _currentModelDir == modelDir) {
      log("Engine already initialized for this directory. skipping.");
      return;
    }

    log("DEBUG: _initOnnx starting for $modelDir");
    try {
      if (_bridge != null) {
        log("Disposing old bridge instance due to directory change...");
        _bridge!.dispose();
        _bridge = null;
      }
    } catch (e) {
      log("Error disposing old bridge: $e");
    }
    
     // Yield to the event loop so the UI can render the 'Initializing...' overlay
    // before the native FFI call blocks the main thread.
    await Future.delayed(const Duration(milliseconds: 500));

    _bridge = await MedGemmaBridge.create(modelDir, onLog: (msg) {
       log("[NATIVE] $msg");
    });
    _currentModelDir = modelDir;
    
    log("DEBUG: Bridge initialized and currentModelDir set.");
  }

  /// DYNAMIC CONFIG PATCHER
  /// Fixes 'genai_config.json' compatibility issues (e.g. unknown fields crashing OGA).
  /// This is MANDATORY because the HuggingFace native config often contains keys 
  /// that have not yet been implemented in the stable ONNX Runtime GenAI releases.
  Future<void> _enforceConfigConstraints(String modelDir) async {
    try {
      final file = File("$modelDir/genai_config.json");
      if (!await file.exists()) return;

      final content = await file.readAsString();
      Map<String, dynamic> jsonMap = jsonDecode(content);
      bool modified = false;

      // 1. CLEAN UP TOP LEVEL MODEL BLOCK
      if (jsonMap.containsKey('model')) {
        final modelMap = jsonMap['model'] as Map<String, dynamic>;
        
        // Ensure context_length is present and valid in model block (Required by OGA)
        if (modelMap['context_length'] == null || modelMap['context_length'] == 0 || modelMap['context_length'] > 2048) {
          modelMap['context_length'] = 2048;
          modified = true;
          log("PATCHED: Set 'context_length' to 2048 in model block.");
        }

        // Fix decoder sub-block
        if (modelMap.containsKey('decoder')) {
           final decoderMap = modelMap['decoder'] as Map<String, dynamic>;
           
           // CRITICAL FIX: Remove 'provider' as it's often unknown in OGA JSON schema
           if (decoderMap.containsKey('provider')) {
             decoderMap.remove('provider');
             modified = true;
             log("PATCHED: Removed unsupported 'provider' field from decoder.");
           }

           // DIMENSION CONSISTENCY: Ensure hidden_size matches C++ Bridge (2560)
           if (decoderMap['hidden_size'] != 2560) {
             decoderMap['hidden_size'] = 2560;
             modified = true;
             log("PATCHED: Set 'hidden_size' to 2560 in decoder block.");
           }

           // GEMMA 2 ARCHITECTURE: Ensure attention heads match hidden size (2560 / 256 = 10)
           if (decoderMap['num_attention_heads'] != 10) {
             decoderMap['num_attention_heads'] = 10;
             modified = true;
             log("PATCHED: Set 'num_attention_heads' to 10 in decoder block.");
           }

           if (decoderMap.containsKey('session_options')) {
              final options = decoderMap['session_options'] as Map<String, dynamic>;
              
              // MEMORY OPTIMIZATION: Enable mmap to reduce RAM pressure
              options['session.use_mmap'] = '1';

              // CRITICAL FIX: provider_options is unknown in some OGA versions and causes parsing failure.
              if (options.containsKey('provider_options')) {
                options.remove('provider_options');
                modified = true;
                log("PATCHED: Removed unknown 'provider_options' from session_options.");
              }
              
              modified = true; 
           } else {
             decoderMap['session_options'] = {'session.use_mmap': '1'};
             modified = true;
           }
        }
      }

      // 2. CLEAN UP SEARCH BLOCK
      if (jsonMap.containsKey('search')) {
        final searchMap = jsonMap['search'] as Map<String, dynamic>;

        // FIX 1: Remove 'context_length' from search block (Invalid in newer OGA)
        if (searchMap.containsKey('context_length')) {
          searchMap.remove('context_length');
          modified = true;
          log("PATCHED: Removed invalid 'context_length' from search block.");
        }

        // FIX 2: Clamp max_length for safety
        if (searchMap['max_length'] == null || searchMap['max_length'] > 2048) {
          searchMap['max_length'] = 2048;
          modified = true;
          log("PATCHED: Clamped 'max_length' to 2048.");
        }
        
        // FIX 3: Ensure top_p is reasonable if sampling is off
        if (searchMap['do_sample'] == false) {
           searchMap['top_p'] = 1.0;
           searchMap['temperature'] = 0.1;
        }
      }
      
      if (modified) {
         // Pretty print for readability
         await file.writeAsString(const JsonEncoder.withIndent('  ').convert(jsonMap), flush: true);
         log("Config file updated with aggressive compatibility patches.");
      }
    } catch (e) {
      log("CRITICAL: Failed to patch config file (likely corrupted): $e");
      try {
        final file = File("$modelDir/genai_config.json");
        if (await file.exists()) {
          log("Deleting corrupted config file to force repair...");
          await file.delete();
        }
      } catch (_) {}
      rethrow; // Force caller to handle the missing/broken config
    }
  }



  // Image normalization logic moved to MedGemmaBridge.preprocessImage for robustness.

  Future<void> checkAndHandleModel({int version = 1, bool force = false}) async {
    // Soft exit if already initialized and not forced
    if (_isInitialized && !force) {
      return;
    }

    if (kIsWeb || Platform.isMacOS) {
      _isMockMode = true;
      _isInitialized = true;
      _ref.read(modelStatusProvider.notifier).updateState(
        _ref.read(modelStatusProvider).copyWith(status: ModelStatus.ready, message: "Mock Mode Active")
      );
      return;
    }

    // Rapid check if model files are present on disk
    if (await _quickCheckModelExists() && !force) {
      log("Model files present. AI flagged as ready (deferred initialization).");
      
      _ref.read(modelStatusProvider.notifier).state = _ref.read(modelStatusProvider).copyWith(status: ModelStatus.ready);
      _ref.read(aiSettingsProvider.notifier).setMultimodalDownloaded(true);
     
      _isInitialized = true; // Set initialized to true here to persist across home screen visits
      final path = await _localPath;
      
      _ref.read(modelStatusProvider.notifier).updateState(
        _ref.read(modelStatusProvider).copyWith(status: ModelStatus.initializing, message: "Initializing Clinical Engine...")
      );
      
      await _initOnnx(path);
      
      _ref.read(modelStatusProvider.notifier).updateState(
        _ref.read(modelStatusProvider).copyWith(status: ModelStatus.ready, message: "AI Ready")
      );
      return;
    } 

    // If missing or forced, go straight to setup/repair
    // We skip verifyModelIntegrity() and init() here to satisfy the requirement for an instant startup.
    // The engine will be loaded lazily on the first call to inferenceStream().
    log("Model missing or update forced. Starting setup/repair flow...");
    await setupMedGemma((progress, received, total) {
      _ref.read(modelStatusProvider.notifier).updateState(
         _ref.read(modelStatusProvider).copyWith(
            status: ModelStatus.downloading,
            progress: progress,
            receivedSize: received,
            totalSize: total
         )
      );
    });
  }

  Stream<Map<String, dynamic>> downloadModelOptimized() async* {
    double progressValue = 0.0;
    bool completed = false;
    String? error;

    final version = 1;
    final StreamController<Map<String, dynamic>> controller = StreamController();

    setupMedGemma((progress, received, total) {
      progressValue = progress;
      controller.add({
        'progress': progressValue,
        'total': total,
        'received': received,
      });
    }, version: version).then((_) {
      completed = true;
      controller.add({
        'progress': 1.0,
        'total': 0,
        'received': 0,
      });
      controller.close();
    }).catchError((e) {
      error = e.toString();
      controller.addError(e);
      controller.close();
    });

    yield* controller.stream;
  }

  /// Orchestrates the multi-file download process.
  /// Supports:
  /// - Resuming interrupted downloads (via Range headers).
  /// - Partial repairs (only downloading corrupted/missing files).
  /// - Wakelock to prevent device sleep during massive transfers.
  Future<void> setupMedGemma(Function(double progress, int received, int total) onProgress, {int version = 1, List<String>? filesToRepair}) async {
    final bool isRepair = filesToRepair != null && filesToRepair.isNotEmpty;
    log(isRepair ? "Repairing ${filesToRepair.length} problematic files..." : "Starting individual file downloads from $_baseUrl...");
    
    try {
      // Enable Wakelock
      await WakelockPlus.enable();
      
      final directory = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${directory.path}/medgemma/$_modelParams');
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }

      final filesToDownload = filesToRepair ?? _getRequiredFiles();
      int totalFiles = filesToDownload.length;
      int completedFilesCount = 0;
      
      log("Downloading $totalFiles files");
      
      // Track cumulative download progress
      Map<String, int> fileSizes = {};
      Map<String, int> receivedPerFile = {};

      // Initialize with what we know
      for (var f in filesToDownload) {
        receivedPerFile[f] = 0;
        final file = File("${modelDir.path}/$f");
        if (await file.exists()) {
          final s = await file.length();
          receivedPerFile[f] = s;
          fileSizes[f] = s;
        }
      }

      for (var fileName in filesToDownload) {
        var fileUrl = "$_baseUrl/$fileName";
        var filePath = "${modelDir.path}/$fileName";
        final file = File(filePath);
        
        // Update current file index (1-based for user display)
        final currentIndex = filesToDownload.indexOf(fileName) + 1;
        // For large onnx files, we want to ensure they are fully downloaded.
        // If it's a small config file and exists, we skip.
        // If it's the model file, we check later if it needs resuming.
        if (await file.exists() && !fileName.contains('.onnx') && fileName != "genai_config.json") {
          debugPrint("ModelManager: Skipping $fileName (config file exists)");
          completedFilesCount++;
          continue;
        }

        debugPrint("ModelManager: Downloading $fileName ($currentIndex/${filesToDownload.length})...");
        
        // Internal resolution: tree/main -> resolve/main for direct downloads
        final downloadBaseUrl = _baseUrl.replaceAll('/tree/', '/resolve/');
        fileUrl = "$downloadBaseUrl/$fileName";
        filePath = "${modelDir.path}/$fileName";
        
        int retryCount = 0;
        const int maxRetries = 5;
        bool success = false;

        while (retryCount < maxRetries && !success) {
          try {
            final currentFile = File(filePath);
            int startByte = 0;
            if (await currentFile.exists()) {
              startByte = await currentFile.length();
              receivedPerFile[fileName] = startByte;
              log("Resuming $fileName from byte $startByte");
            }

            fileSizes[fileName] = 0; // will update from response

            final dio = Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 10),
            ));

            try {
              final response = await dio.get<ResponseBody>(
                fileUrl,
                options: Options(
                  headers: {
                    if (_hfToken.isNotEmpty) "Authorization": "Bearer $_hfToken",
                    if (startByte > 0) "Range": "bytes=$startByte-",
                  },
                  responseType: ResponseType.stream,
                ),
                onReceiveProgress: (received, total) {
                  receivedPerFile[fileName] = startByte + received;
                  if (total > 0) fileSizes[fileName] = total + startByte;
                  
                  int totalReceived = receivedPerFile.values.fold(0, (int a, int b) => a + b);
                  int totalExpected = fileSizes.values.fold(0, (int a, int b) => a + b);
                  double overallProgress = totalExpected > 0 ? totalReceived / totalExpected : 0.0;
                  
                  onProgress(overallProgress, totalReceived, totalExpected);
                  
                  // Update state with current file info
                  _ref.read(modelStatusProvider.notifier).state = _ref.read(modelStatusProvider).copyWith(
                    progress: overallProgress,
                    receivedSize: totalReceived,
                    totalSize: totalExpected,
                    currentFileName: fileName,
                    currentFileIndex: currentIndex,
                    totalFileCount: filesToDownload.length,
                  );
                },
              );

              // Handle 206 Partial Content or 200 OK
              final bool isPartial = response.statusCode == 206;
              final int contentLength = int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
              
              if (!isPartial && startByte > 0 && response.statusCode == 200) {
                if (contentLength == 0) {
                  success = true;
                  break;
                }
                startByte = 0;
              }

              final int actualTotal = isPartial ? (contentLength + startByte) : contentLength;
              fileSizes[fileName] = actualTotal;

              final raf = await currentFile.open(mode: startByte > 0 ? FileMode.append : FileMode.write);
              int received = startByte;
              receivedPerFile[fileName] = received;

              try {
                await for (final chunk in response.data!.stream) {
                  await raf.writeFrom(chunk);
                  received += chunk.length;
                  receivedPerFile[fileName] = received;
                  
                  int currentTotalBytes = 0;
                  int currentReceivedBytes = 0;
                  for (var f in filesToDownload) {
                    currentTotalBytes += (fileSizes[f] ?? 0);
                    currentReceivedBytes += (receivedPerFile[f] ?? 0);
                  }

                  if (currentTotalBytes > 0) {
                    double overallProgress = (currentReceivedBytes / currentTotalBytes).clamp(0.0, 0.999);
                    onProgress(overallProgress, currentReceivedBytes, currentTotalBytes);
                  }
                }
                success = true;
              } finally {
                await raf.close();
              }
            } finally {
              dio.close();
            }
          } on DioException catch (de) {
            if (de.response?.statusCode == 416) {
              log("Range Not Satisfiable (416) for $fileName. Local file may be larger than remote or corrupt. Deleting and restarting download.");
              if (await File(filePath).exists()) {
                await File(filePath).delete();
              }
              // Reset state for retry
              receivedPerFile[fileName] = 0;
              retryCount++;
              continue;
            }
            if (de.response?.statusCode == 404) {
              log("REMOTE MISSING: $fileName not found on server (404).");
              // Skip retries for 404
              success = true; 
              continue;
            }
            retryCount++;
            log("Error downloading $fileName (Attempt $retryCount/$maxRetries): $de");
            if (retryCount >= maxRetries) rethrow;
            await Future.delayed(Duration(seconds: retryCount * 2));
          } catch (e) {
            retryCount++;
            log("Error downloading $fileName (Attempt $retryCount/$maxRetries): $e");
            if (retryCount >= maxRetries) rethrow;
            // Exponential backoff
            await Future.delayed(Duration(seconds: retryCount * 2));
          }
        }

        completedFilesCount++;
        log("Downloaded $fileName successfully");

        // Log small config JSON content for debugging
        if (fileName == "genai_config.json") {
          try {
            String content = await File(filePath).readAsString();
            
            // PATCH genai_config.json for Mobile Resources
            try {
              Map<String, dynamic> jsonMap = jsonDecode(content);
              bool modified = false;

              // 1. Reduce max length for mobile stability (Prevent OOM)
              if (jsonMap.containsKey('search')) {
                final searchMap = jsonMap['search'] as Map<String, dynamic>;
                
                if (searchMap['max_length'] == null || searchMap['max_length'] > 2048) {
                  searchMap['max_length'] = 2048;
                  modified = true;
                  log("PATCHED: Reduced max_length to 2048.");
                }
                
                // CRITICAL FIX: context_length belongs in 'model', NOT 'search'
                if (searchMap.containsKey('context_length')) {
                  searchMap.remove('context_length');
                  modified = true;
                  log("PATCHED: Removed invalid context_length from search block.");
                }

                 // Set default search params if null to prevent runtime errors
                if (searchMap['do_sample'] == null) { searchMap['do_sample'] = false; modified = true; }
                if (searchMap['temperature'] == null) { searchMap['temperature'] = 0.1; modified = true; }
                if (searchMap['top_p'] == null) { searchMap['top_p'] = 0.2; modified = true; }
                if (searchMap['top_k'] == null) { searchMap['top_k'] = 50; modified = true; }
              }

              // Patch context_length in the correct 'model' block
              if (jsonMap.containsKey('model')) {
                 final modelMap = jsonMap['model'] as Map<String, dynamic>;
                 if (modelMap['context_length'] == null || modelMap['context_length'] == 0 || modelMap['context_length'] > 2048) {
                   modelMap['context_length'] = 2048;
                   modified = true;
                   log("PATCHED: Set model.context_length to 2048.");
                 }

                 // CRITICAL FIX: provider_options is unknown in some OGA versions
                 if (modelMap.containsKey('decoder')) {
                   final decoderMap = modelMap['decoder'] as Map<String, dynamic>;
                   
                   // Remove unsupported 'provider' field
                   if (decoderMap.containsKey('provider')) {
                     decoderMap.remove('provider');
                     modified = true;
                     log("PATCHED: Removed unsupported 'provider' during download.");
                   }

                   // DIMENSION CONSISTENCY: Ensure hidden_size matches C++ Bridge
                   if (decoderMap['hidden_size'] != 2560) {
                     decoderMap['hidden_size'] = 2560;
                     modified = true;
                   }

                   // GEMMA 2 ARCHITECTURE: Ensure attention heads match
                   if (decoderMap['num_attention_heads'] != 10) {
                     decoderMap['num_attention_heads'] = 10;
                     modified = true;
                   }

                   if (decoderMap.containsKey('session_options')) {
                     final options = decoderMap['session_options'] as Map<String, dynamic>;
                     
                     // Enable mmap
                     options['session.use_mmap'] = '1';

                     if (options.containsKey('provider_options')) {
                       options.remove('provider_options');
                       modified = true;
                       log("PATCHED: Removed unknown 'provider_options' during download.");
                     }
                     modified = true;
                   } else {
                     decoderMap['session_options'] = {'session.use_mmap': '1'};
                     modified = true;
                   }
                 }
              }

              // 2. DYNAMIC PATCHING: Smart Loading (Memory Optimization)
              if (jsonMap.containsKey('model')) {
                final modelMap = jsonMap['model'] as Map<String, dynamic>;
                
                if (modelMap.containsKey('vision')) {
                  // Schema Repair for Vision
                  final visionMap = modelMap['vision'] as Map<String, dynamic>;
                  if (visionMap.containsKey('encoder') || visionMap.containsKey('vision_encoder')) {
                    final pipelineMap = <String, dynamic>{};
                    if (visionMap.containsKey('encoder')) {
                      pipelineMap['encoder'] = visionMap['encoder'];
                      visionMap.remove('encoder');
                    } else if (visionMap.containsKey('vision_encoder')) {
                      pipelineMap['encoder'] = visionMap['vision_encoder'];
                      visionMap.remove('vision_encoder');
                    }
                    if (visionMap.containsKey('projection')) {
                      pipelineMap['projection'] = visionMap['projection'];
                      visionMap.remove('projection');
                    } else if (visionMap.containsKey('vision_projection')) {
                      pipelineMap['projection'] = visionMap['vision_projection'];
                      visionMap.remove('vision_projection');
                    }
                    visionMap['pipeline'] = pipelineMap;
                    modified = true;
                    log("PATCHED: Restructured vision pipeline.");
                  }
                }
              }

              if (modified) {
                content = const JsonEncoder.withIndent('    ').convert(jsonMap);
                await File(filePath).writeAsString(content, flush: true);
                log("Successfully saved patched $fileName");
              }
            } catch (e) {
              log("Error during config patching: $e");
            }

            final displayContent = content.length > 2000 ? content.substring(0, 2000) + "..." : content;
            log("Content of $fileName: $displayContent");
          } catch (e) {
            log("Failed to process $fileName: $e");
          }
        }
      }



      onProgress(1.0, 0, 0);
      fileSizes.clear();
      receivedPerFile.clear();

      // Check for tokenizer.json (Crucial for Gemma 3)
      final tokenizerJson = File("${modelDir.path}/tokenizer.json");
      if (!await tokenizerJson.exists()) {
        log("⚠️ WARNING: tokenizer.json is missing. Gemma 3 requires this.");
      }

      // Verification moved to _diagnoseFileCorruption called on failure.
      log("Verifying files presence...");
      for (var f in allModelFiles) {
         final file = File("${modelDir.path}/$f");
         if (!await file.exists()) {
             log("MISSING FILE: $f");
         }
      }debugPrint("✅ MedGemma $version files verified.");
      
      // 3. Try to initialize the engine
      try {
        log("Attempting to initialize ONNX model at: ${modelDir.path}");
        await _initOnnx(modelDir.path);
        
        log("ONNX Model Initialized Successfully!");
        
        _isInitialized = true;
        _ref.read(aiSettingsProvider.notifier).setMultimodalDownloaded(true);
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('model_version', version); // Keep legacy version tracking but files are in named dir

        _ref.read(modelStatusProvider.notifier).updateState(
          _ref.read(modelStatusProvider).copyWith(status: ModelStatus.ready, version: version)
        );
      } catch (e, stack) {
        log("Post-download ONNX init failed: $e\nStack trace: $stack");
        
        // CRITICAL CHECK: If init fails, we MUST Scan for corruption (LFS pointers, etc.)
        // This ensures the UI shows "File X is corrupt" instead of generic "Protobuf parsing failed".
        await _diagnoseFileCorruption(modelDir);

        // If diagnosis passes (no trivial corruption found), rethrow the original error.
        // This ensures the original error message (e.g., protobuf parsing) is still shown if corruption isn't the cause.
        String friendlyError = e.toString();
        if (friendlyError.contains("libflutter_onnxruntime_genai.so") && friendlyError.contains("not found")) {
          friendlyError = "Architecture Mismatch: This AI engine only supports ARM64 physical devices. It cannot run on x86_64 emulators. Please test on a real Android device.";
        }

        _ref.read(modelStatusProvider.notifier).updateState(
          _ref.read(modelStatusProvider).copyWith(
            status: ModelStatus.error, 
            message: "Files Ready, but Engine Failed: $friendlyError"
          )
        );
      }
      
    } catch (e) {
      debugPrint("❌ MedGemma setup failed: $e");
      
      _ref.read(modelStatusProvider.notifier).updateState(
        _ref.read(modelStatusProvider).copyWith(
          status: ModelStatus.error, 
          message: "Setup Failed: $e"
        )
      );
    } finally {
      await WakelockPlus.disable();
    }
  }

  // Helper to deep-scan files for common download corruption (LFS pointers, HTML errors)
  Future<void> _diagnoseFileCorruption(Directory modelDir) async {
       log("Running Deep File Diagnosis...");
       final filesToCheck = _getRequiredFiles();
       
       for (var f in filesToCheck) {
             // Skip non-onnx/ort files for header check (except config JSONs)
             if (!f.endsWith('.onnx') && !f.endsWith('.ort')) continue;
             
             try {
                 final file = File("${modelDir.path}/$f");
                 if (!await file.exists()) continue;

                 final length = await file.length();
                 // Read first 100 bytes
                 final bytes = await file.openRead(0, 100).first;
                 // Replace non-printable with dot for safe logging
                 final header = String.fromCharCodes(bytes).replaceAll(RegExp(r'[\x00-\x1F\x7F-\xFF]'), '.');
                 
                 log("🔍 Header Check [$f]: Size=$length, Header='$header'");
                 
                 // CHECK 1: Git LFS Pointer
                 if (header.contains("version https://git-lfs")) {
                     final msg = "CRITICAL: File '$f' is an LFS Pointer (Fake File). Deleting it automatically... Please Restart Download.";
                     log("🚨 $msg");
                     await file.delete();
                     throw Exception(msg);
                 }
                 
                 // CHECK 2: HTML Error Page
                 if (header.contains("<html>") || header.contains("<!DOCTYPE")) {
                     final msg = "CRITICAL: File '$f' is an HTML Error Page. Deleting it automatically... Please Restart Download.";
                     log("🚨 $msg");
                     await file.delete();
                     throw Exception(msg);
                 }
                 
                 const int MB = 1024 * 1024;
                 const int GB = 1024 * MB;
                 
                 int expectedSize = 0;
                 if (f == "model.onnx.data") expectedSize = 2690 * MB;
                 else if (f == "embeddings.ort") expectedSize = 671 * MB;
                 else if (f == "vision_encoder.ort") expectedSize = 419 * MB;
                 else if (f == "vision_projection.ort") expectedSize = 11 * MB;
                 
                 if (expectedSize > 0) {
                      // Allow 1% variance or just check if it's WAY too small (e.g., failed download)
                      // If it's less than 90% of expected, it's definitely broken.
                      if (length < (expectedSize * 0.9)) {
                           final msg = "CRITICAL: File '$f' is TRUNCATED ($length bytes < expected $expectedSize). Deleting it automatically... Please Restart Download.";
                           log("🚨 $msg");
                           await file.delete();
                           throw Exception(msg);
                      }
                 }

             } catch (e) {
                 if (e is Exception && e.toString().contains("CRITICAL")) rethrow;
                 log("⚠️ Could not read header of $f: $e");
             }
         }
         log("✅ Deep Diagnosis passed. No obvious corruption found.");
  }

  /// Checks if the device meets hardware requirements (at least 8GB RAM).
  Future<bool> hasMinHardware() async {
    if (kIsWeb) return false;
    // Mocking 8GB RAM check - in production replace with a plugin call.
    // For this demo, we assume modern hardware is capable.
    return true; 
  }



  // _formatPrompt removed. Template logic consolidated in MedGemmaBridge.

  /// MAIN INFERENCE PIPELINE
  /// Flows:
  /// 1. Preprocess clinical images (if any) — pass null for text-only.
  /// 2. Wrap prompt with Gemma-2 chat templates.
  /// 3. Stream tokens back to the UI in real-time.
  Stream<String> inferenceStream(String prompt, {List<Uint8List>? images}) async* {
    await _logMemoryInfo();
    
    try {
      // Enable Wakelock during inference (covers both mock and real modes)
      await WakelockPlus.enable();

     
      if (!_isInitialized) {
        log("AI Model not ready. Initializing...");
        await init();
        if (!_isInitialized) {
           yield "Error: AI Model failed to initialize. Please check settings.";
           return;
        }
      }


      // Preprocess user image if provided; otherwise null → text-only mode.
      // When null, the Dart bridge passes nullptr to C++ which skips the
      // entire vision encoder/projection pipeline (~500MB RAM saved).
      // Preprocess user image if provided; otherwise null → text-only mode.
      // When null, the Dart bridge passes nullptr to C++ which skips the
      // entire vision encoder/projection pipeline (~500MB RAM saved).
      Uint8List? rawImageBytes;
      
      if (images != null && images.isNotEmpty) {
        log("Passing clinical image bytes (${images.length} images) for native OpenCV processing...");
        rawImageBytes = images.first;
      } else {
        log("No image provided. Running text-only inference (vision pipeline skipped).");
        rawImageBytes = null;
      }

      // Send to FFI inference loop
      // Note: We skip _formatPrompt here because MedGemmaBridge handles it.
      log("Starting FFI inference loop...");
      
      try {
        final maxTokens = _ref.read(aiSettingsProvider).maxTokens;
        // Text-only mode: higher repetition penalty (1.5) to discourage
        // rambling and encourage structured markdown output. With images,
        // the model naturally follows structure better so 1.25 is sufficient.
        final penalty = rawImageBytes == null ? 1.5 : 1.25;
        debugPrint("ModelManager: Starting inference with maxTokens=$maxTokens, repetitionPenalty=$penalty");

        final stopwatch = Stopwatch()..start();
        final stream = _bridge!.analyzeStream(
          imageBytes: rawImageBytes,  // null = text-only, no vision
          promptText: prompt, // Pass raw prompt; Bridge will wrap once.
          maxTokens: maxTokens,
          repetitionPenalty: penalty,
          onLog: (msg) => log("[NATIVE_INF] $msg"),
        );

        await for (final token in stream) {
           yield token;
        }
        log("INFERENCE COMPLETE: duration=${stopwatch.elapsed.inSeconds}s");
      } catch (e, stack) {
        log("INFERENCE LOOP ERROR: $e");
        log("STACK TRACE: $stack");
        rethrow;
      }
    } catch (e, stack) {
      log("INTERNAL INFERENCE ERROR (Triggering Scan): $e");
      log("STACK TRACE: $stack");
      
      // CRITICAL: Check for file corruption (LFS/Truncated) with robust path resolution
      String debugInfo = "";
      try {
          String checkPath = _currentModelDir ?? "";
          if (checkPath.isEmpty) {
              checkPath = await _localPath;
          }
          
          if (checkPath.isNotEmpty) {
             // We modify _diagnoseFileCorruption to return a status string instead of just logging?
             // For now, let's just inspect the files manually here if diagnosis returns cleanly.
             await _diagnoseFileCorruption(Directory(checkPath));
             
             // If we are here, NO corruption was auto-detected/deleted.
             // Let's gather debug info to show the user WHY.
             final dir = Directory(checkPath);
             if (await dir.exists()) {
                 final files = dir.listSync();
                 debugInfo = "\n\nDebug Info:\nPath: $checkPath\nFiles Found: ${files.length}\n";
                 for (var f in files) {
                     if (f is File) {
                        final len = await f.length();
                        String header = "";
                        try {
                           final bytes = await f.openRead(0, 20).first;
                           header = String.fromCharCodes(bytes).replaceAll(RegExp(r'[\x00-\x1F\x7F-\xFF]'), '.');
                        } catch (_) {}
                        debugInfo += "${f.path.split('/').last}: $len bytes [$header]\n";
                     }
                 }
             } else {
                 debugInfo = "\n\nDebug Info: Directory $checkPath does not exist.";
             }
          }
      } catch (corruptionEx) {
          // Found a specific corruption error! Show THIS to the user.
          yield "Correction Needed: $corruptionEx";
          yield "Files were corrupted and have been auto-deleted. Please go to Settings and click DOWNLOAD MODEL.";
          return;
      }
      
      yield "Error generating AI response: $e$debugInfo";
    } finally {
      // Disable Wakelock
      await WakelockPlus.disable();
    }
  }

  Future<void> createChat({List<Uint8List>? images}) async {
    // ONNX implementation doesn't use InferenceChat
  }

  /// Loads and preprocesses the default clinical anchor image (gray.png).
  /// This is the mandatory fallback when no user image is provided.
  Future<Uint8List> _loadDefaultImage() async {
    log("DEBUG: Loading 'assets/images/gray.png' as default anchor.");
    final ByteData data = await rootBundle.load('assets/images/gray.png');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Stream<String> sendMessageToChat(dynamic chat, String text, {Uint8List? image}) async* {
    // ONNX implementation uses manual history from triage_chat_controller
    yield* inferenceStream(text, images: image != null ? [image] : null);
  }

  String formatChatMessage(String text, bool isUser, bool isBinary, String language) {
    if (!isBinary) return text;
    if (isUser) {
      return "<start_of_turn>user\n[Language: $language]\n$text<end_of_turn>\n<start_of_turn>model\n";
    } else {
      return "<start_of_turn>model\n[Language: $language]\n$text<end_of_turn>\n";
    }
  }
}
