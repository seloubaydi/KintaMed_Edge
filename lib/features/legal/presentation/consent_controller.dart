import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/presentation/settings_controller.dart';

class ConsentNotifier extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool('user_consent_given') ?? false;
  }

  Future<void> acceptConsent() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('user_consent_given', true);
    state = true;
  }
}

final consentProvider = NotifierProvider<ConsentNotifier, bool>(ConsentNotifier.new);
