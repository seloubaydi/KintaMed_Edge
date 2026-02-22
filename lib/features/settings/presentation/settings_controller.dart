import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/localization/app_localizations.dart';

class AISettings {
  final int maxTokens;
  final Locale locale;
  final bool isModelDownloaded;

  AISettings({
    required this.maxTokens,
    required this.locale,
    this.isModelDownloaded = false,
  });

  AISettings copyWith({
    int? maxTokens,
    Locale? locale,
    bool? isModelDownloaded,
  }) {
    return AISettings(
      maxTokens: maxTokens ?? this.maxTokens,
      locale: locale ?? this.locale,
      isModelDownloaded: isModelDownloaded ?? this.isModelDownloaded,
    );
  }
}

class AISettingsNotifier extends Notifier<AISettings> {
  @override
  AISettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    
    // Default to English only for now as per user request
    const locale = Locale('en', 'US');
    
    return AISettings(
      maxTokens: prefs.getInt('ai_max_tokens') ?? 1024,
      locale: locale,
      isModelDownloaded: prefs.getBool('ai_model_downloaded') ?? false,
    );
  }

  Future<void> setMaxTokens(int value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt('ai_max_tokens', value);
    state = state.copyWith(maxTokens: value);
  }

  Future<void> setMultimodalDownloaded(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('ai_model_downloaded', value);
    state = state.copyWith(isModelDownloaded: value);
  }

}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

final aiSettingsProvider = NotifierProvider<AISettingsNotifier, AISettings>(AISettingsNotifier.new);
