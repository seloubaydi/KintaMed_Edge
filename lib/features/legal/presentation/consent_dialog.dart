import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gap/gap.dart';
import '../../../core/theme/app_theme.dart';
import 'legal_screen.dart';
import 'consent_controller.dart';

class ConsentDialog extends ConsumerWidget {
  const ConsentDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = Localizations.localeOf(context).languageCode;
    final privacyPath = lang == 'en' ? 'docs/PRIVACY_POLICY.md' : 'docs/PRIVACY_POLICY_$lang.md';
    final termsPath = lang == 'en' ? 'docs/TERMS_OF_SERVICE.md' : 'docs/TERMS_OF_SERVICE_$lang.md';

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.gavel_rounded, color: AppTheme.primary),
            const Gap(12),
            Text(
              'KintaMed Edge',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please review and accept our guidelines to ensure safe and ethical use of clinical AI.',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
              ),
              const Gap(20),
              _LegalLink(
                title: 'Privacy Policy',
                onTap: () => _showLegal(context, 'Privacy Policy', privacyPath),
              ),
              const Gap(12),
              _LegalLink(
                title: 'Terms of Service',
                onTap: () => _showLegal(context, 'Terms of Service', termsPath),
              ),
              const Gap(24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        'All clinical AI suggestions must be reviewed and approved by a qualified medical expert.',
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ref.read(consentProvider.notifier).acceptConsent();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: AppTheme.background,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'I AGREE & ACCEPT',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLegal(BuildContext context, String title, String path) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalScreen(title: title, assetPath: path),
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _LegalLink({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
