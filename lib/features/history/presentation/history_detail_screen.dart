import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/app_localizations.dart';
import '../../triage/domain/entities/triage_entities.dart';
import '../../intake/presentation/intake_screen.dart';
import '../../../core/utils/pdf_generator.dart';

class HistoryDetailScreen extends StatelessWidget {
  final Assessment assessment;
  final Patient patient;

  const HistoryDetailScreen({
    super.key,
    required this.assessment,
    required this.patient,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateStr = DateFormat('MMMM dd, yyyy • HH:mm').format(assessment.timestamp);

    Color statusColor;
    if (assessment.urgencyColor == "Red") {
      statusColor = AppTheme.error;
    } else if (assessment.urgencyColor == "Yellow") {
      statusColor = AppTheme.warning;
    } else {
      statusColor = AppTheme.success;
    }

    final displayText = (assessment.aiPrediction ?? "")
        .replaceAll("[ANALYSIS_COMPLETE]", "")
        .replaceAll("[ANALYSIS_COMPLETE_WITH_ERRORS]", "")
        .trim();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.translate('assessment_details') ?? 'Assessment Details'),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Patient Info Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppTheme.primary.withOpacity(0.1),
                          child: const Icon(Icons.person, color: AppTheme.primary),
                        ),
                        const Gap(16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                patient.name,
                                style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                "${patient.age}y • ${patient.gender}",
                                style: const TextStyle(color: Colors.white60),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: statusColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            assessment.urgencyColor?.toUpperCase() ?? "UNKNOWN",
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Gap(16),
                    const Divider(color: Colors.white10),
                    const Gap(16),
                    _buildInfoRow(Icons.calendar_today_outlined, l10n.translate('date') ?? "Date", dateStr),
                    const Gap(8),
                    _buildInfoRow(
                      Icons.monitor_heart_outlined, 
                      l10n.translate('vitals') ?? "Vitals", 
                      "BP ${assessment.systolic}/${assessment.diastolic} | HR ${assessment.heartRate} | SpO2 ${assessment.spo2}%",
                    ),
                  ],
                ),
              ),
              const Gap(32),
  
              // Reasoning Section
              Text(
                l10n.translate('clinical_reasoning') ?? "Clinical Reasoning",
                style: const TextStyle(fontSize: 20, color: AppTheme.primary, fontWeight: FontWeight.bold),
              ),
              const Gap(16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: MarkdownBody(
                  data: displayText.isEmpty ? "No reasoning registered." : displayText,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 16, height: 1.5, color: Colors.white70),
                    h1: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    h2: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    h3: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    listBullet: const TextStyle(color: AppTheme.primary),
                  ),
                ),
              ),
              const Gap(40),
  
              // Share PDF Report Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white10,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () async {
                  try {
                    await PdfGenerator.generateAndShareReport(assessment);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.translate('failed_to_generate_pdf') ?? "Failed to generate PDF")),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(l10n.translate('share_pdf_report') ?? "Share PDF Report"),
              ),
              const Gap(16),
  
              // Start New Assessment Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => IntakeScreen(
                        existingPatient: patient,
                        lastAssessment: assessment,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.add_circle_outline),
                label: Text(
                  l10n.translate('start_new_assessment') ?? "Start New Assessment",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Gap(24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white38),
        const Gap(8),
        Text("$label: ", style: const TextStyle(color: Colors.white38, fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
