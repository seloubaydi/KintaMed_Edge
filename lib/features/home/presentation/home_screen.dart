import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ai/model_manager.dart';
import '../../../core/localization/app_localizations.dart';
import '../../intake/presentation/intake_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../history/presentation/history_screen.dart';
import '../../legal/presentation/legal_screen.dart';
import '../../legal/presentation/consent_controller.dart';
import '../../legal/presentation/consent_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize model check on startup
    // Initialize model check on startup
    Future.microtask(() async {
      final manager = ref.read(modelManagerProvider);
      await manager.checkAndHandleModel();
      
      // If model is present/downloaded, we no longer trigger background load (Lazy Loading)
      if (mounted && ref.read(modelStatusProvider).status == ModelStatus.ready) {
        debugPrint("HomeScreen: Model is ready. Lazy loading active.");
      }
      
      // Check for user consent on first launch
      if (mounted) {
        final hasConsented = ref.read(consentProvider);
        if (!hasConsented) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const ConsentDialog(),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final modelState = ref.watch(modelStatusProvider);
    final l10n = AppLocalizations.of(context);
  
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Header Section
                    const _HeaderSection(),
                    
                    const Gap(24),

                    // Model Progress Section (if downloading or checking)
                    if (modelState.status == ModelStatus.downloading || 
                        modelState.status == ModelStatus.checking ||
                        modelState.status == ModelStatus.error)
                      _ModelDownloadSection(state: modelState)
                    else if (modelState.status == ModelStatus.ready && modelState.message != null)
                       Padding(
                         padding: const EdgeInsets.only(bottom: 16),
                         child: Text(
                           modelState.message!,
                           style: GoogleFonts.inter(color: AppTheme.primary, fontSize: 12),
                         ),
                       ),

                    // Security Notice Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Text(
                        l10n.translate('this_application_is_secure'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),

                    const Gap(32),

                    // Main Action Buttons
                    _MainActions(size: size, isReady: modelState.status == ModelStatus.ready, l10n: l10n),

                    const Gap(48),

                    // Footer Section
                    _FooterSection(isReady: modelState.status == ModelStatus.ready),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (modelState.status == ModelStatus.initializing)
          const _InitializingOverlay(),
      ],
    );
  }
}

class _InitializingOverlay extends StatelessWidget {
  const _InitializingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'KintaMed',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  TextSpan(
                    text: ' Edge',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 500.ms),
            const Gap(32),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05), duration: 1500.ms, curve: Curves.easeInOut)
             .shimmer(duration: 2000.ms, color: AppTheme.primary.withOpacity(0.2)),
            const Gap(32),
            Text(
              "Initialization...",
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .fadeIn(duration: 1000.ms)
             .then()
             .fadeOut(duration: 1000.ms),
            const Gap(16),
            const SizedBox(
              width: 150,
              child: LinearProgressIndicator(
                backgroundColor: Colors.white10,
                color: AppTheme.primary,
                minHeight: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelDownloadSection extends ConsumerWidget {
  final ModelDownloadState state;
  const _ModelDownloadSection({required this.state, super.key});

  String _formatBytes(int bytes) {
    if (bytes <=0) return "0 B";
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    String title = l10n.translate('preparing_clinical_intelligence');
    String description = l10n.translate('ensuring_the_latest_medical_database_is_ready');
    Color accentColor = AppTheme.primary;

    if (state.status == ModelStatus.downloading) {
      title = l10n.translate('downloading_clinical_intelligence');
      description = l10n.translate('fetching_the_medical_reasoning_database');
    } else if (state.status == ModelStatus.error) {
       title = l10n.translate('download_failed');
       // Show the actual error message from the logic (e.g. "Engine Failed")
       description = state.message ?? l10n.translate('connectivity_issue_detected');
       accentColor = Colors.redAccent;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.1),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: state.status == ModelStatus.error 
                  ? const Icon(Icons.sync_problem_rounded, color: Colors.redAccent)
                  : SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        value: (state.status == ModelStatus.downloading) ? state.progress : null,
                        strokeWidth: 2,
                        color: accentColor,
                      ),
                    ),
              ),
              const Gap(16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (state.status == ModelStatus.downloading) ...[
            const Gap(16),
            Stack(
              children: [
                Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 12,
                      width: constraints.maxWidth * state.progress.clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withOpacity(0.6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    );
                  }
                ),
              ],
            ),
            const Gap(12),
            // Current file info
            if (state.currentFileName != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      state.currentFileName!,
                      style: GoogleFonts.firaCode(
                        color: AppTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Gap(8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      "${state.currentFileIndex}/${state.totalFileCount}",
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatBytes(state.receivedSize),
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      "of ${_formatBytes(state.totalSize)}",
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                  ),
                  child: Text(
                    "${(state.progress * 100).clamp(0.0, 100.0).toStringAsFixed(1)}%",
                    style: GoogleFonts.outfit(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (state.status == ModelStatus.error) ...[
            const Gap(16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref.read(modelManagerProvider).checkAndHandleModel(force: true);
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(l10n.translate("retry_download")),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showLogDialog(context, state.logs),
                    icon: const Icon(Icons.terminal_rounded, size: 18),
                    label: const Text("View Logs"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1, end: 0);
  }

  void _showLogDialog(BuildContext context, List<String> logs) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          "Setup Logs",
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.infinity,
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
                  fontSize: 11,
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
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const Gap(20),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'KintaMed',
                          style: GoogleFonts.outfit(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: ' Edge',
                          style: GoogleFonts.outfit(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(4),
                  Text(
                    l10n.translate('Expert_care_slogan'),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 500.ms);
  }
}

class _MainActions extends StatelessWidget {
  final Size size;
  final bool isReady;
  final AppLocalizations l10n;
  const _MainActions({required this.size, required this.isReady, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: isReady ? () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IntakeScreen())
              );
            } : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.background,
              disabledBackgroundColor: Colors.white10,
              disabledForegroundColor: Colors.white24,
              elevation: isReady ? 4 : 0,
              shadowColor: AppTheme.primary.withOpacity(0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown, // Scales the text down to fit, but not up
              child: Text(
                          isReady ? l10n.translate('start_assessment').toUpperCase() : l10n.translate('initializing').toUpperCase(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            
                          ),
                        ),
            ),
           
          ),
        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0),

        const Gap(16),

        Row(
          children: [
            Expanded(
              child: _SecondaryActionCard(
                icon: Icons.list_alt_rounded,
                label: l10n.translate('view_history'),
                onTap: () {
                   Navigator.of(context).push(
                     MaterialPageRoute(builder: (_) => const HistoryScreen())
                   );
                },
              ),
            ),
            const Gap(16),
            Expanded(
              child: _SecondaryActionCard(
                icon: Icons.settings_rounded,
                label: l10n.translate('settings'),
                onTap: () {
                   Navigator.of(context).push(
                     MaterialPageRoute(builder: (_) => const SettingsScreen())
                   );
                },
              ),
            ),
          ],
        ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0),
      ],
    );
  }
}

class _SecondaryActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SecondaryActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 140, 
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: AppTheme.primary),
              const Gap(16),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterSection extends StatelessWidget {
  final bool isReady;
  const _FooterSection({required this.isReady});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        if (isReady)
          Text(
            l10n.translate('offline_ready_private'),
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight  .w600,
              color: Colors.white70,
              decoration: TextDecoration.underline,
              decorationColor: AppTheme.primary,
            ),
          ).animate().fadeIn(duration: 400.ms),
        if (isReady) const Gap(16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () {
                final lang = Localizations.localeOf(context).languageCode;
                final assetPath = lang == 'en' ? 'docs/PRIVACY_POLICY.md' : 'docs/PRIVACY_POLICY_$lang.md';
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LegalScreen(
                      title: l10n.translate('Privacy_Policy'),
                      assetPath: assetPath,
                    ),
                  ),
                );
              }, 
              child: Text(
                l10n.translate('Privacy_Policy'),
                 style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 12,
                 ),
              )
            ),
             const Text('|', style: TextStyle(color: Colors.white12)),
             TextButton(
              onPressed: () {
                final lang = Localizations.localeOf(context).languageCode;
                final assetPath = lang == 'en' ? 'docs/TERMS_OF_SERVICE.md' : 'docs/TERMS_OF_SERVICE_$lang.md';
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LegalScreen(
                      title: l10n.translate('Terms_of_Service'),
                      assetPath: assetPath,
                    ),
                  ),
                );
              }, 
              child: Text(
                l10n.translate('Terms_of_Service'),
                 style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 12,
                 ),
              )
            ),
          ],
        )
      ],
    ).animate().fadeIn(delay: 600.ms);
  }
}
