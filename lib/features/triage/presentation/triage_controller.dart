import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/model_manager.dart';
import '../../triage/data/repositories/triage_repository.dart';
import '../../triage/domain/entities/triage_entities.dart';
import '../../settings/presentation/settings_controller.dart';
import 'package:intl/intl.dart';
import '../../history/data/providers/history_providers.dart';
import '../../../core/localization/app_localizations.dart';


final triageControllerProvider = NotifierProvider.autoDispose<TriageController, AsyncValue<Assessment?>>(TriageController.new);

class TriageController extends Notifier<AsyncValue<Assessment?>> {
  
  @override
  AsyncValue<Assessment?> build() {
    final modelManager = ref.read(modelManagerProvider);
    ref.onDispose(() {
      // We no longer dispose the model here.
      // The model should remain loaded in the background for faster re-triage.
      // Explicit disposal can be done via Settings if needed.
    });
    return const AsyncData(null);
  }

  Future<void> performTriage(Assessment assessment) async {
    state = const AsyncLoading();
    final modelManager = ref.read(modelManagerProvider);
    modelManager.log("DEBUG: performTriage started for ${assessment.id}");
    
    try {
      final repo = ref.read(triageRepositoryProvider);
      await repo.saveAssessment(assessment);
      
      // The modelManager is already read above, but we can reuse the variable or read again.
      // For clarity and to ensure it's the same instance, we'll just use the one declared above.
      // final modelManager = ref.read(modelManagerProvider); // This line is now redundant if we use the one above
      if (!modelManager.isInitialized) {
        await modelManager.init();
      }

      Assessment currentAssessment = assessment;
      
      // Fetch historical data for this patient
      final history = await repo.getAssessmentsForPatient(assessment.patientId);
      final previousAssessments = history.where((a) => a.id != assessment.id).take(3).toList();
      
      // === UNIFIED PRIORITY DIAGNOSTIC ===
      debugPrint("TriageController: Starting Unified Diagnostic Stream...");
      final unifiedPrompt = _buildUnifiedPrompt(assessment, history: previousAssessments);

      // Set state to initial data immediately so UI transitions from loading spinner to result layout
      state = AsyncData(currentAssessment);

      // 3. Inference with image support
      // Fallback to white.jpeg is now handled centrally in ModelManager
      final stream = modelManager.inferenceStream(unifiedPrompt, images: assessment.images);
      
      bool colorDetected = false;
      String fullResponse = "";

      await for (final partialText in stream) {
        fullResponse += partialText;
        String? urgColor = currentAssessment.urgencyColor;
        
        // 1. Instant Category Detection (Tag-based or Keyword-based)
        if (!colorDetected) {
          final detectText = fullResponse.toLowerCase();
          
          if (detectText.contains("red") || detectText.contains("rouge") || detectText.contains("rojo") || detectText.contains("[triage:red]")) {
            urgColor = "Red";
            colorDetected = true;
          } else if (detectText.contains("yellow") || detectText.contains("jaune") || detectText.contains("amarillo") || detectText.contains("[triage:yellow]")) {
            urgColor = "Yellow";
            colorDetected = true;
          } else if (detectText.contains("green") || detectText.contains("vert") || detectText.contains("verde") || detectText.contains("[triage:green]")) {
            urgColor = "Green";
            colorDetected = true;
          }
        }

        // 2. Clean up display text (hide internal tags, strange block characters, and "thought" blocks)
        String cleanDisplay = ModelManager.cleanAiText(fullResponse);
        
       

        currentAssessment = currentAssessment.copyWith(
          aiPrediction: cleanDisplay,
          urgencyColor: urgColor,
          reasoning: _extractReasoning(cleanDisplay),
        );
        state = AsyncData(currentAssessment);
      }
      
      // Final completion tag
      currentAssessment = currentAssessment.copyWith(
        aiPrediction: "${currentAssessment.aiPrediction ?? ""}\n\n[ANALYSIS_COMPLETE]"
      );

      // Final Save
      await repo.saveAssessment(currentAssessment);
      ref.invalidate(historyProvider);
      state = AsyncData(currentAssessment);
      debugPrint("TriageController: Unified analysis completed.");

    } catch (e, stack) {
      debugPrint("TriageController Error: $e");
      String errorMsg = e.toString();
      if (errorMsg.contains("OUT_OF_RANGE") || errorMsg.contains("maxTokens") || errorMsg.contains("input_size")) {
        final enhancedError = Exception(
          "Input too long for AI model.\n\n"
          "The clinical data exceeds the current 'Model Intelligence (maxTokens)' limit.\n\n"
          "Solution: Go to Settings → Increase 'Model Intelligence' to 4096.\n\n"
          "Technical details: $errorMsg"
        );
        state = AsyncValue.error(enhancedError, stack);
      } else {
        state = AsyncValue.error(e, stack);
      }
    }
  }

  /// Updates the current assessment manually (used by chat for triage updates)
  Future<void> updateAssessment(Assessment updated) async {
    if (state.hasValue && state.value != null) {
      final repo = ref.read(triageRepositoryProvider);
      await repo.saveAssessment(updated);
      ref.invalidate(historyProvider);
      state = AsyncData(updated);
    }
  }

  /// Releases image bytes held by the current assessment in memory.
  /// Call this when returning to the home screen so Android can reclaim
  /// the raw Uint8List buffers. The model engine is NOT touched.
  void clearAssessmentImages() {
    if (state.hasValue && state.value != null) {
      state = AsyncData(state.value!.copyWith(clearImages: true));
      debugPrint("TriageController: Assessment images cleared from memory.");
    }
  }



  // These methods are no longer needed as we use Stream directly in performTriage
  
  // --- UNIFIED PROMPT BUILDERS ---

  String _buildUnifiedPrompt(Assessment a, {List<Assessment>? history}) {
    final aiSettings = ref.read(aiSettingsProvider);
    final loc = AppLocalizations(aiSettings.locale);
    final hasImages = a.images != null && a.images!.isNotEmpty;
    
    String historyContext = "";
    if (history != null && history.isNotEmpty) {
      historyContext = "\n${loc.translate('prompt_history_summary')}\n";
      for (var prev in history) {
        historyContext += "- ${DateFormat('MMM dd', aiSettings.locale.languageCode).format(prev.timestamp)}: ${prev.urgencyColor}";
        if (prev.reasoning != null && prev.reasoning!.isNotEmpty) {
          historyContext += " (${_summarizeReasoning(prev.reasoning)})";
        }
        historyContext += "\n";
      }
    }
    
    const targetLanguage = 'english';
    final maxTokensResult = aiSettings.maxTokens;
    
    // Build vitals string conditionally
    String vitalsSummary = "- ${loc.translate('prompt_vitals')} ";
    List<String> vitalsParts = [];
    if (a.systolic != null && a.diastolic != null) vitalsParts.add("BP ${a.systolic}/${a.diastolic}");
    if (a.heartRate != null) vitalsParts.add("HR ${a.heartRate}");
    if (a.temperature != null) vitalsParts.add("Temp ${a.temperature}°C");
    if (a.spo2 != null) vitalsParts.add("SpO2 ${a.spo2}%");
    
    if (vitalsParts.isEmpty) {
      vitalsSummary = "";
    } else {
      vitalsSummary += vitalsParts.join(", ");
    }

    final unknown = loc.translate('unknown');

    final prompt = """
${loc.translate('prompt_intro')}
- ${loc.translate('prompt_age')} ${a.age != null ? "${a.age}y" : unknown}
- ${loc.translate('prompt_gender')} ${a.gender ?? unknown}
- $vitalsSummary
${a.glucose != null ? "- ${loc.translate('prompt_Glucose')}: ${a.glucose} mg/dL\n" : ""}${a.height != null ? "- ${loc.translate('prompt_Height')}: ${a.height} cm\n" : ""}${a.weight != null ? "- ${loc.translate('prompt_Weight')}: ${a.weight} kg\n" : ""}${a.allergies != null && a.allergies!.isNotEmpty ? "- ${loc.translate('prompt_Allergies')}: ${a.allergies!.join(', ')}\n" : ""}
$historyContext

${loc.translate('prompt_structure_triage')}

${loc.translate('prompt_begin_immediately')} 


Question: ${loc.translate('prompt_in_less_than')} ${maxTokensResult} ${loc.translate('prompt_tokens')}, ${hasImages ? "${loc.translate('prompt_images_analysis')}" : ""} ${loc.translate('prompt_treatment_plan')} ${a.symptoms}.

End your response with "---END OF REPORT---" to indicate that you have completed the analysis.
""";

    debugPrint("TriageController: Generated Prompt in $targetLanguage:\n$prompt");
    return prompt;
  }

 


  String _summarizeReasoning(String? reasoning) {
    if (reasoning == null || reasoning.isEmpty) return "";
    final sentences = reasoning.split(RegExp(r'(?<=[.!?])\s+'));
    if (sentences.length <= 2) return reasoning;
    final summary = sentences.take(2).join(" ");
    if (summary.length > 200) return "${summary.substring(0, 200)}...";
    return summary;
  }

  String _extractReasoning(String response) {
    // For the preview card, clean tags and take a snippet
    String cleaned = response.replaceAll(RegExp(r'\[TRIAGE:[A-Z]+\]', caseSensitive: false), "").trim();
    if (cleaned.length > 500) return "${cleaned.substring(0, 500)}...";
    return cleaned;
  }
}
