import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/ai/model_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/app_localizations.dart';
import '../../triage/domain/entities/triage_entities.dart';
import '../../../core/utils/pdf_generator.dart';
import 'triage_controller.dart';
import 'triage_chat_controller.dart';

class TriageScreen extends ConsumerStatefulWidget {
  final Assessment assessment;

  const TriageScreen({super.key, required this.assessment});

  @override
  ConsumerState<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends ConsumerState<TriageScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger triage as soon as we land, or check model first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRun();
    });
  }

  Future<void> _checkAndRun() async {
    final modelManager = ref.read(modelManagerProvider);
    final exists = await modelManager.checkModelExists();
    
    if (!exists) {
      if (mounted) _showDownloadDialog();
    } else {
      // 800ms delay to ensure transition animation finishes
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        ref.read(triageControllerProvider.notifier).performTriage(widget.assessment);
      }
    }
  }

  void _showDownloadDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _DownloadDialog(),
    ).then((_) {
       // Retry after download
       ref.read(triageControllerProvider.notifier).performTriage(widget.assessment);
    });
  }

  @override
  void dispose() {
    // Free image bytes and chat context when the screen is removed
    // (e.g. system back button). The model engine stays loaded.
    _releaseAssessmentMemory();
    super.dispose();
  }

  void _releaseAssessmentMemory() {
    // Nulls the image bytes stored in the Assessment object and resets the
    // follow-up chat context. Also reloads the vision encoder sessions to
    // free ~430 MB of previous image working RAM. 
    // The main model engine is NOT touched — no re-init.
    try {
      ref.read(modelManagerProvider).resetInferenceState();
      
      if (ref.exists(triageControllerProvider)) {
        ref.read(triageControllerProvider.notifier).clearAssessmentImages();
      }
      if (ref.exists(triageChatProvider)) {
        ref.read(triageChatProvider.notifier).resetChat();
      }
    } catch (_) {
      // Providers may already be auto-disposed at this point — safe to ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(triageControllerProvider);
    final l10n = AppLocalizations.of(context);

    // Listen for triage updates from the follow-up chat
    ref.listen<TriageChatState>(triageChatProvider, (previous, next) {
      if (next.updatedTriageCategory != null && 
          next.updatedTriageCategory != previous?.updatedTriageCategory) {
        
        final assessment = state.value;
        if (assessment != null && assessment.urgencyColor != next.updatedTriageCategory) {
          // Update the assessment with the new category
          final updated = assessment.copyWith(urgencyColor: next.updatedTriageCategory);
          ref.read(triageControllerProvider.notifier).updateAssessment(updated);
          
          // Show notification to the user
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      "TRIAGE UPDATED: The severity has been updated to ${next.updatedTriageCategory!.toUpperCase()} based on new information.",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: next.updatedTriageCategory == "Red" 
                  ? AppTheme.error 
                  : (next.updatedTriageCategory == "Yellow" ? AppTheme.warning : AppTheme.success),
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          
          // Haptic feedback for visibility
          HapticFeedback.heavyImpact();
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.translate('triage_analysis'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: state.when(
            data: (assessment) {
              if (assessment == null) return Center(child: Text(l10n.translate('initializing')));
              return _buildResult(assessment, l10n);
            },
            error: (err, stack) => SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.error, size: 64),
                    const Gap(16),
                    Text(l10n.translate('inference_error'), style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                    const Gap(16),
                    Text(l10n.translate('error_message'), textAlign: TextAlign.center),
                    const Gap(16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.error.withValues(alpha: 0.5)),
                      ),
                      child: SelectableText(
                        "$err\n\nStacktrace:\n$stack",
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Gap(24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(0, 50),
                            ),
                            onPressed: () => ref.read(triageControllerProvider.notifier).performTriage(widget.assessment),
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.translate('retry')),
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                              minimumSize: const Size(0, 50),
                            ),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: "$err\n\nStacktrace:\n$stack"));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.translate('error_copied'))),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            label: Text(l10n.translate('copy_text')),
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.error,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      onPressed: () async {
                        await ref.read(modelManagerProvider).deleteModel();
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.translate('model_deleted_message'))),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete_forever),
                      label: Text(l10n.translate('delete_redownload_model')),
                    ),
                    const Gap(24),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(l10n.translate('back_to_intake'), style: const TextStyle(color: Colors.white60)),
                    ),
                  ],
                ),
              ),
            ),
            loading: () {
              final modelState = ref.watch(modelStatusProvider);
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                     const CircularProgressIndicator(color: AppTheme.primary),
                     const Gap(24),
                     Text(
                       l10n.translate('analyzing_clinical_data'),
                       style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                     ),
                     const Gap(8),
                     Text(
                       modelState.message ?? l10n.translate('waking_up_ai_intelligence'),
                       textAlign: TextAlign.center,
                       style: const TextStyle(color: Colors.white60, fontSize: 14),
                     ),
                     if (modelState.status == ModelStatus.checking) ...[
                       const Gap(24),
                       const Text(
                         "This usually takes 10-30 seconds depending on device speed.",
                         style: TextStyle(color: Colors.white38, fontSize: 12),
                       ),
                     ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResult(Assessment a, AppLocalizations l10n) {
    bool isPending = a.urgencyColor == null;
    
    Color statusColor;
    if (isPending) {
      statusColor = Colors.grey;
    } else if (a.urgencyColor == "Red") {
      statusColor = AppTheme.error;
    } else if (a.urgencyColor == "Yellow") {
      statusColor = AppTheme.warning;
    } else {
      statusColor = AppTheme.success;
    }

    final predictionText = a.aiPrediction ?? "";
    final isComplete = predictionText.contains("[ANALYSIS_COMPLETE]") || predictionText.contains("[ANALYSIS_COMPLETE_WITH_ERRORS]");
    final displayText = predictionText
        .replaceAll("[ANALYSIS_COMPLETE]", "")
        .replaceAll("[ANALYSIS_COMPLETE_WITH_ERRORS]", "")
        .trim();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              border: Border.all(color: statusColor, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                if (isPending) ...[
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                    ),
                  ),
                  const Gap(16),
                  Text(
                    l10n.translate('determining_category') ?? "DETERMINING CATEGORY...",
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ] else ...[
                  Text(
                    a.urgencyColor?.toUpperCase() ?? "...",
                    style: GoogleFonts.outfit(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ],
                const Gap(8),
                Text(l10n.translate('recommended_triage_category') ?? "Recommended Triage Category"),
              ],
            ).animate(target: isPending ? 0 : 1).shimmer(duration: const Duration(seconds: 2), color: statusColor.withValues(alpha: 0.3)),
          ),
          const Gap(32),
          Text(l10n.translate('clinical_reasoning') ?? "Clinical Reasoning", style: TextStyle(fontSize: 20, color: AppTheme.primary, fontWeight: FontWeight.bold)),
          const Gap(16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: MarkdownBody(
              data: displayText.isEmpty ? l10n.translate('initializing_triage_engine') ?? "Initializing triage engine..." : displayText,
              styleSheet: MarkdownStyleSheet(
                p: GoogleFonts.inter(fontSize: 15, height: 1.6, color: Colors.white.withOpacity(0.85)),
                h1: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.primary, height: 1.4),
                h2: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primary, height: 1.4),
                h3: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white, height: 1.4),
                h4: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.9), height: 1.4),
                h5: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.8), height: 1.4),
                h6: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.7), height: 1.4),
                h1Padding: const EdgeInsets.only(top: 24, bottom: 8),
                h2Padding: const EdgeInsets.only(top: 20, bottom: 8),
                h3Padding: const EdgeInsets.only(top: 16, bottom: 4),
                h4Padding: const EdgeInsets.only(top: 12, bottom: 4),
                listBullet: GoogleFonts.inter(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold),
                listBulletPadding: const EdgeInsets.only(right: 8),
                listIndent: 24.0,
                blockSpacing: 16.0,
                a: const TextStyle(color: AppTheme.primary, decoration: TextDecoration.underline),
                strong: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                em: TextStyle(fontStyle: FontStyle.italic, color: Colors.white.withOpacity(0.7)),
                code: GoogleFonts.firaCode(fontSize: 13, color: Colors.greenAccent, backgroundColor: Colors.black26),
                codeblockDecoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                horizontalRuleDecoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white12, width: 1)),
                ),
              ),
            ),
          ),
          if (isComplete) ...[
            const Gap(32),
            _ClinicalFollowUpChat(assessment: a, initialResult: displayText),
            const Gap(32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () async {
                try {
                  final chatState = ref.read(triageChatProvider);
                  await PdfGenerator.generateAndShareReport(
                    a.copyWith(aiPrediction: displayText),
                    chatHistory: chatState.messages,
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.translate('failed_to_generate_pdf') ?? "Failed to generate PDF: $e")),
                    );
                  }
                }
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(l10n.translate('share_pdf_report') ?? "Share PDF Report"),
            ),
          ],
          const Gap(12),
          ElevatedButton(
            onPressed: () {
              // Free image bytes and chat context before returning home.
              // The model engine stays loaded — no re-init needed.
              _releaseAssessmentMemory();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: Text(l10n.translate('return_to_dashboard') ?? "Return to Dashboard"),
          ),
          const Gap(48),
        ],
      ),
    );
  }
}

class _ClinicalFollowUpChat extends ConsumerStatefulWidget {
  final Assessment assessment;
  final String initialResult;

  const _ClinicalFollowUpChat({
    required this.assessment,
    required this.initialResult,
  });

  @override
  ConsumerState<_ClinicalFollowUpChat> createState() => _ClinicalFollowUpChatState();
}

class _ClinicalFollowUpChatState extends ConsumerState<_ClinicalFollowUpChat> {
  final TextEditingController _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(triageChatProvider.notifier).initializeChat(widget.assessment, widget.initialResult);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(triageChatProvider);
      final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('follow_up_clinical_questions') ?? "Follow-up Clinical Questions",
          style: TextStyle(fontSize: 20, color: AppTheme.primary, fontWeight: FontWeight.bold),
        ),
        const Gap(16),
        Container(
          height: 400,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: chatState.messages.length,
                  separatorBuilder: (_, __) => const Gap(16),
                  itemBuilder: (context, index) {
                    final msg = chatState.messages[index];
                    // Skip index 0 as it's the duplicate of the clinical reasoning
                    if (index == 0) return const SizedBox.shrink();
                    
                    return Column(
                      crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: msg.isUser ? AppTheme.primary.withValues(alpha: 0.1) : Colors.black26,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: msg.isUser ? AppTheme.primary.withValues(alpha: 0.3) : Colors.white10,
                            ),
                          ),
                          child: MarkdownBody(
                            data: msg.text,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ),
                        ),
                        const Gap(4),
                        Text(
                          msg.isUser ? l10n.translate('you') ?? "You" : l10n.translate('medical_ai') ?? "Medical AI",
                          style: const TextStyle(fontSize: 10, color: Colors.white38),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (chatState.isTyping)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: LinearProgressIndicator(minHeight: 2, color: AppTheme.primary),
                ),
              if (chatState.error != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(chatState.error!, style: const TextStyle(color: AppTheme.error, fontSize: 12)),
                ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: l10n.translate('ask_about_this_case') ?? "Ask about this case...",
                          hintStyle: const TextStyle(color: Colors.white24),
                          fillColor: Colors.black26,
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        onSubmitted: (val) {
                          if (val.isNotEmpty && !chatState.isTyping) {
                            ref.read(triageChatProvider.notifier).sendMessage(val);
                            _chatController.clear();
                          }
                        },
                      ),
                    ),
                    const Gap(8),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppTheme.primary),
                      onPressed: chatState.isTyping 
                        ? null 
                        : () {
                          if (_chatController.text.isNotEmpty) {
                            ref.read(triageChatProvider.notifier).sendMessage(_chatController.text);
                            _chatController.clear();
                          }
                        },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(delay: 400.ms);
  }
}

class _DownloadDialog extends ConsumerWidget {
  const _DownloadDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Model Manager download stream
    // Note: In Riverpod, watching a stream needs a StreamProvider or similar.
    // For simplicity, we'll use a StreamBuilder here calling the manager directly 
    // or through a provider if we defined one. 
    // We didn't define a stream provider, so let's call the method.
    
    final manager = ref.watch(modelManagerProvider);
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(l10n.translate('downloading_medical_model') ?? "Downloading Medical Model"),
      content: SizedBox(
        height: 120,
        child: StreamBuilder<Map<String, dynamic>>(
          stream: manager.downloadModelOptimized(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text("Error: ${snapshot.error}", style: const TextStyle(color: AppTheme.error));
            }
            if (snapshot.connectionState == ConnectionState.done) {
               WidgetsBinding.instance.addPostFrameCallback((_) {
                 if (Navigator.canPop(context)) Navigator.pop(context);
               });
               return const Center(child: Icon(Icons.check_circle, color: AppTheme.success, size: 50));
            }
            final data = snapshot.data;
            final progress = data?['progress'] as double? ?? 0.0;
            final received = data?['received'] as int? ?? 0;
            final total = data?['total'] as int? ?? 0;
            
            String sizeText = "";
            if (total > 0) {
              final receivedMB = (received / (1024 * 1024)).toStringAsFixed(1);
              final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
              sizeText = "$receivedMB MB / $totalMB MB";
            }

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 LinearProgressIndicator(value: progress, color: AppTheme.primary),
                 const Gap(10),
                 Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                     Text("${(progress * 100).toStringAsFixed(1)}%", style: const TextStyle(fontWeight: FontWeight.bold)),
                     if (sizeText.isNotEmpty) 
                       Text(sizeText, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                   ],
                 ),
                 const Gap(10),
                 Text(
                   l10n.translate('downloading_medgemma') ?? "Downloading MedGemma 3 Intelligence...",
                   style: const TextStyle(fontSize: 12)
                 ),
                 if (progress > 0 && progress < 1.0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      "File ${((progress * 6).ceil().clamp(1, 6))} of 6",
                      style: const TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
