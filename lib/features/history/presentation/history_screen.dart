import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/app_localizations.dart';
import '../../triage/domain/entities/triage_entities.dart';
import '../../triage/data/repositories/triage_repository.dart';
import '../../triage/presentation/triage_screen.dart';
import '../../intake/presentation/intake_screen.dart';
import '../data/providers/history_providers.dart';
import 'history_detail_screen.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(historyProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.translate('assessment_history') ?? 'Assessment History'),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: l10n.translate('search_patients') ?? 'Search patients...',
                  hintStyle: const TextStyle(color: Colors.white30),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                  filled: true,
                  fillColor: AppTheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: historyAsync.when(
                data: (items) {
                  final filtered = items.where((item) {
                    final patient = item['patient'] as Patient?;
                    if (patient == null) return false;
                    return patient.name.toLowerCase().contains(_searchQuery);
                  }).toList();
  
                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.history_outlined, size: 64, color: Colors.white24),
                          const Gap(16),
                          Text(
                            l10n.translate('no_history_found') ?? 'No history found',
                            style: const TextStyle(color: Colors.white38),
                          ),
                        ],
                      ),
                    );
                  }
  
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final assessment = item['assessment'] as Assessment;
                      final patient = item['patient'] as Patient;
                      
                      return _HistoryCard(
                        assessment: assessment,
                        patient: patient,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => HistoryDetailScreen(
                                assessment: assessment,
                                patient: patient,
                              ),
                            ),
                          );
                        },
                        onStartNew: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => IntakeScreen(
                                existingPatient: patient,
                                lastAssessment: assessment,
                              ),
                            ),
                          );
                        },
                        onDelete: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: AppTheme.surface,
                              title: Text(
                                l10n.translate('delete_assessment') ?? 'Delete Assessment',
                                style: const TextStyle(color: Colors.white),
                              ),
                              content: Text(
                                l10n.translate('confirm_delete') ?? 'Are you sure you want to delete this assessment?',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: Text(l10n.translate('cancel') ?? 'Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                                  child: Text(l10n.translate('delete') ?? 'Delete'),
                                ),
                              ],
                            ),
                          );
  
                          if (confirmed == true) {
                            await ref.read(triageRepositoryProvider).deleteAssessment(assessment.id);
                            ref.invalidate(historyProvider);
                          }
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: AppTheme.error))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Assessment assessment;
  final Patient patient;
  final VoidCallback onTap;
  final VoidCallback onStartNew;
  final VoidCallback onDelete;

  const _HistoryCard({
    required this.assessment,
    required this.patient,
    required this.onTap,
    required this.onStartNew,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM dd, yyyy • HH:mm').format(assessment.timestamp);
    
    Color statusColor;
    if (assessment.urgencyColor == "Red") {
      statusColor = AppTheme.error;
    } else if (assessment.urgencyColor == "Yellow") {
      statusColor = AppTheme.warning;
    } else {
      statusColor = AppTheme.success;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient.name,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          "${patient.age}y • ${patient.gender}",
                          style: const TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
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
              const Gap(12),
              const Divider(color: Colors.white10, height: 1),
              const Gap(12),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: Colors.white38),
                  const Gap(6),
                  Text(dateStr, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onStartNew,
                    icon: const Icon(Icons.add_circle_outline, size: 18, color: AppTheme.primary),
                    label: const Text("New Assessment", style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.error),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
