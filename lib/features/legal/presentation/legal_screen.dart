import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gap/gap.dart';
import '../../../core/theme/app_theme.dart';

class LegalScreen extends StatelessWidget {
  final String title;
  final String assetPath;

  const LegalScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppTheme.background,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: FutureBuilder(
          future: rootBundle.loadString(assetPath),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              );
            }
  
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error loading document',
                  style: GoogleFonts.inter(color: Colors.white60),
                ),
              );
            }
  
            return Markdown(
              data: snapshot.data ?? '',
              styleSheet: MarkdownStyleSheet(
                h1: GoogleFonts.outfit(
                  color: AppTheme.primary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                h2: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                p: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.5,
                ),
                listBullet: GoogleFonts.inter(color: AppTheme.primary),
                blockquote: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
                blockquoteDecoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: AppTheme.primary, width: 4)),
                  color: Colors.white10,
                ),
                blockquotePadding: const EdgeInsets.all(16),
              ),
            );
          },
        ),
      ),
    );
  }
}
