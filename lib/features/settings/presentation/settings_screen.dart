import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/app_localizations.dart';
import 'settings_controller.dart';
import '../../../core/ai/model_manager.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _showLogDialog(BuildContext context, List<String> logs) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          "Setup & Native Logs",
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.7,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                logs.isEmpty ? "No logs available." : logs.join("\n"),
                style: GoogleFonts.firaCode(
                  color: Colors.greenAccent,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aiSettingsProvider);
    final notifier = ref.read(aiSettingsProvider.notifier);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('app_settings'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Gap(16),
            _buildSectionHeader(l10n.translate('ai_performance')),
            const Gap(16),
            _buildSettingCard(
              title: l10n.translate('model_intelligence'),
              subtitle: l10n.translate('model_intelligence_desc'),
              child: Column(
                children: [
                  Slider(
                    value: settings.maxTokens >= 1024 ? settings.maxTokens.toDouble() : 1024,
                    min: 1024,
                    max: 4096,
                    divisions: 12,
                    label: settings.maxTokens.toString(),
                    activeColor: AppTheme.primary,
                    onChanged: (val) => notifier.setMaxTokens(val.toInt()),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${l10n.translate('fast')} (1024)", style: const TextStyle(fontSize: 12, color: Colors.white54)),
                        Text("${l10n.translate('current')}: ${settings.maxTokens < 1024 ? 1024 : settings.maxTokens}", style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                        Text("${l10n.translate('detailed')} (4096)", style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Gap(24),
            const Gap(24),
            _buildSettingCard(
              title: l10n.translate('model_management'),
              subtitle: l10n.translate('model_management_desc'),
              child: FutureBuilder<bool>(
                future: ref.read(modelManagerProvider).hasMinHardware(),
                builder: (context, snapshot) {
                  final bool hasMinHardware = snapshot.data ?? false;
                  if (!hasMinHardware) {
                     return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l10n.translate('device_incompatible'), style: const TextStyle(color: Colors.redAccent)),
                    );
                  }
  
                  return Column(
                    children: [
                      ListTile(
                        title: Text(settings.isModelDownloaded ? l10n.translate('model_downloaded') : l10n.translate('model_missing')),
                        subtitle: Text(settings.isModelDownloaded ? l10n.translate('system_ready') : l10n.translate('download_required')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.sync_rounded, color: AppTheme.primary),
                              onPressed: () => ref.read(modelManagerProvider).checkModelExists(),
                              tooltip: "Sync status",
                            ),
                            settings.isModelDownloaded ? const Icon(Icons.check_circle, color: AppTheme.primary) : const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                          ],
                        ),
                      ),
                      if (!settings.isModelDownloaded) ...[
                        if (ref.read(modelStatusProvider).problematicFiles.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Problematic Files (${ref.read(modelStatusProvider).problematicFiles.length}):",
                                  style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                ...ref.read(modelStatusProvider).problematicFiles.take(3).map((f) => Text(
                                  "• $f",
                                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                                )),
                                if (ref.read(modelStatusProvider).problematicFiles.length > 3)
                                  const Text("• ...and others", style: TextStyle(color: Colors.white60, fontSize: 10)),
                                const Gap(12),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                ref.read(modelManagerProvider).checkAndHandleModel();
                                Navigator.of(context).pop(); 
                              },
                              icon: Icon(ref.read(modelStatusProvider).problematicFiles.length < ref.read(modelManagerProvider).allModelFiles.length ? Icons.build_circle_rounded : Icons.download_rounded),
                              label: Text(
                                (ref.read(modelStatusProvider).problematicFiles.isNotEmpty && 
                                 ref.read(modelStatusProvider).problematicFiles.length < ref.read(modelManagerProvider).allModelFiles.length)
                                 ? "REPAIR MODEL (${ref.read(modelStatusProvider).problematicFiles.length} FILES)"
                                 : l10n.translate('download_model').toUpperCase()
                              ),
                            ),
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            if (settings.isModelDownloaded)
                              Expanded(
                                child: OutlinedButton.icon(
                                   onPressed: () => ref.read(modelManagerProvider).deleteModel(),
                                   icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                   label: Text(l10n.translate('delete_model').toUpperCase(), style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                                   style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
                                ),
                              ),
                            if (settings.isModelDownloaded) const Gap(8),
                            Expanded(
                              child: OutlinedButton.icon(
                                 onPressed: () => _showLogDialog(context, ref.read(modelStatusProvider).logs),
                                 icon: const Icon(Icons.terminal_rounded, color: Colors.white70),
                                 label: const Text("VIEW LOGS", style: TextStyle(color: Colors.white70, fontSize: 11)),
                                 style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Gap(40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.outfit(
        fontSize: 14,
        letterSpacing: 1.2,
        fontWeight: FontWeight.bold,
        color: AppTheme.primary,
      ),
    );
  }

  Widget _buildSettingCard({required String title, required String subtitle, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Gap(4),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white38)),
              ],
            ),
          ),
          const Gap(8),
          child,
          const Gap(16),
        ],
      ),
    );
  }
}
