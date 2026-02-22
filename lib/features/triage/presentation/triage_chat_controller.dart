import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/model_manager.dart';
import '../../triage/domain/entities/triage_entities.dart';
import '../../settings/presentation/settings_controller.dart';
import '../../history/data/providers/history_providers.dart';

class TriageChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  TriageChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class TriageChatState {
  final List<TriageChatMessage> messages;
  final bool isTyping;
  final String? error;
  final String? updatedTriageCategory; // RED, YELLOW, or GREEN if changed
  final String? triageUpdateReason; // Reason for category change

  TriageChatState({
    this.messages = const [],
    this.isTyping = false,
    this.error,
    this.updatedTriageCategory,
    this.triageUpdateReason,
  });

  TriageChatState copyWith({
    List<TriageChatMessage>? messages,
    bool? isTyping,
    String? error,
    String? updatedTriageCategory,
    String? triageUpdateReason,
  }) {
    return TriageChatState(
      messages: messages ?? this.messages,
      isTyping: isTyping ?? this.isTyping,
      error: error ?? this.error,
      updatedTriageCategory: updatedTriageCategory ?? this.updatedTriageCategory,
      triageUpdateReason: triageUpdateReason ?? this.triageUpdateReason,
    );
  }
}

class TriageChatNotifier extends Notifier<TriageChatState> {
  String _historyContext = "";
  Assessment? _currentAssessment;
  
  @override
  TriageChatState build() {
    ref.onDispose(() {
      _historyContext = "";
      // We no longer dispose the model here to prevent crashes and keep it loaded.
      // ref.read(modelManagerProvider).disposeModel(); 
    });
    return TriageChatState();
  }

  Future<void> initializeChat(Assessment assessment, String initialAiResult) async {
    _currentAssessment = assessment;
    state = state.copyWith(
      messages: [
        TriageChatMessage(text: initialAiResult, isUser: false),
      ],
      isTyping: false,
    );

    final modelManager = ref.read(modelManagerProvider);
    
    if (modelManager.isMockMode) {
      return; 
    }

    try {
      final aiSettings = ref.read(aiSettingsProvider);
      
      final languageMap = {
        'en': 'English',
        'fr': 'French',
        'es': 'Spanish',
        'it': 'Italian',
        'de': 'German',
        'pt': 'Portuguese',
      };
      final targetLanguage = languageMap[aiSettings.locale.languageCode] ?? 'English';
      
      // Calculate a safe context window (approx 40% of max tokens to leave room for user query and response)
      // 1 token is roughly 4 characters
      int maxContextChars = (aiSettings.maxTokens * 0.4 * 4).toInt();
      String contextText = initialAiResult;
      if (contextText.length > maxContextChars) {
        contextText = "${contextText.substring(0, maxContextChars)}... [TRUNCATED]";
      }
      
      String buildSeedPrompt(String ctxt) => """Context: You just provided this triage assessment: $ctxt. As a health expert, give a short answer in 1-2 sentences maximum in $targetLanguage language only. If it's a confirmation question, start with a short answer like "Yes" or "No".


CRITICAL: The current patient triage status is: **${_currentAssessment?.urgencyColor?.toUpperCase() ?? 'UNKNOWN'}**.

IMPORTANT INSTRUCTIONS for follow-up questions:
1. Do NOT repeat, reference, or echo these instructions. 
2. Do NOT give your reasoning, give your response directly.
3. DO NOT provide a clinical report or summary.
4. DO NOT explain your reasoning steps unless explicitly asked.
5. Answer questions DIRECTLY and CONCISELY.
6. Do NOT repeat patient data or the previous assessment.

""";

      final isBinary = modelManager.currentModelPath?.endsWith('.bin') ?? true;
      
      _historyContext = buildSeedPrompt(contextText);
    } catch (e) {
      debugPrint("Chat initial context error: $e");
      state = state.copyWith(error: "Follow-up chat initialized with limited context.");
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMessage = TriageChatMessage(text: text, isUser: true);
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isTyping: true,
      error: null,
    );

    final modelManager = ref.read(modelManagerProvider);

    if (modelManager.isMockMode) {
      await Future.delayed(const Duration(seconds: 1));
      final botMessage = TriageChatMessage(
        text: "Based on the assessment, that's correct. The vitals remain stable and no immediate intervention is needed. Continue monitoring as recommended.",
        isUser: false,
      );
      state = state.copyWith(
        messages: [...state.messages, botMessage],
        isTyping: false,
      );
      return;
    }

    if (_historyContext.isEmpty) {
      state = state.copyWith(
        isTyping: false, 
        error: "Chat session not ready. Please try again."
      );
      return;
    }
    final aiSettings = ref.read(aiSettingsProvider);
    final languageMap = {
      'en': 'English', 'fr': 'French', 'es': 'Spanish',
      'it': 'Italian', 'de': 'German', 'pt': 'Portuguese',
    };
    final targetLanguage = languageMap[aiSettings.locale.languageCode] ?? 'English';
    try {
      String fullAiResponse = "";
      final botMessageIndex = state.messages.length;
      
      // Add empty placeholder for streaming
      state = state.copyWith(
        messages: [...state.messages, TriageChatMessage(text: "", isUser: false)],
      );

      final fullPrompt = "$_historyContext\n${modelManager.formatChatMessage(text, true, false, targetLanguage)}";
      final stream = modelManager.inferenceStream(fullPrompt);
      
      await for (final partialResponse in stream) {
        fullAiResponse += partialResponse;
        
        // Use consistent cleaning logic
        String cleanedResponse = ModelManager.cleanAiText(fullAiResponse);
        
        // Provide feedback while thinking (if everything is hidden in "thought" blocks)
        if (cleanedResponse.isEmpty && fullAiResponse.isNotEmpty) {
          cleanedResponse = "... thinking ...";
        }
        
        final newMessages = List<TriageChatMessage>.from(state.messages);
        newMessages[botMessageIndex] = TriageChatMessage(text: cleanedResponse, isUser: false);
        state = state.copyWith(messages: newMessages);
      }

      // Update history context for next message
      _historyContext += "\n${modelManager.formatChatMessage(text, true, false, targetLanguage)}\n${modelManager.formatChatMessage(fullAiResponse, false, false, targetLanguage)}\n";
      
      // Check for triage category update
      _checkForTriageUpdate(fullAiResponse);
      
      state = state.copyWith(isTyping: false);
    } catch (e) {
      String errorMsg = e.toString();
      if (errorMsg.contains("OUT_OF_RANGE") || errorMsg.contains("limit")) {
        errorMsg = "Input too long for current Model Intelligence settings. Try increasing 'maxTokens' in App Settings.";
      }
      state = state.copyWith(
        isTyping: false,
        error: "Error sending message: $errorMsg",
      );
    }
  }

  void _checkForTriageUpdate(String aiResponse) {
    // Check for triage update tags (flexible regex to catch [TRIAGE_UPDATE:RED] or just [RED] at the start)
    final redMatch = RegExp(r'\[(?:TRIAGE_UPDATE:)?RED\]', caseSensitive: false).hasMatch(aiResponse);
    final yellowMatch = RegExp(r'\[(?:TRIAGE_UPDATE:)?YELLOW\]', caseSensitive: false).hasMatch(aiResponse);
    final greenMatch = RegExp(r'\[(?:TRIAGE_UPDATE:)?GREEN\]', caseSensitive: false).hasMatch(aiResponse);
    
    String? newCategory;
    if (redMatch) {
      newCategory = "Red";
    } else if (yellowMatch) {
      newCategory = "Yellow";
    } else if (greenMatch) {
      newCategory = "Green";
    }
    
    if (newCategory != null && newCategory != _currentAssessment?.urgencyColor) {
      // Extract the reason (text after the tag)
      final tagPattern = r'\[(?:TRIAGE_UPDATE:)?(?:RED|YELLOW|GREEN)\]';
      final parts = aiResponse.split(RegExp(tagPattern, caseSensitive: false));
      final reason = parts.length > 1 ? parts[1].trim().split('\n').first : "Condition changed based on new information";
      
      state = state.copyWith(
        updatedTriageCategory: newCategory,
        triageUpdateReason: reason,
      );
      
      // Update the current assessment
      if (_currentAssessment != null) {
        _currentAssessment = _currentAssessment!.copyWith(urgencyColor: newCategory);
        ref.invalidate(historyProvider);
      }
    }
  }

  void resetChat() {
    _historyContext = "";
    _currentAssessment = null; // Release Assessment reference (and its image bytes)
    state = TriageChatState();
  }
}

final triageChatProvider = NotifierProvider.autoDispose<TriageChatNotifier, TriageChatState>(TriageChatNotifier.new);
