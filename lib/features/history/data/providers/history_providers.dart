import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../triage/data/repositories/triage_repository.dart';
import '../../../triage/domain/entities/triage_entities.dart';

final historyProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(triageRepositoryProvider);
  final assessments = await repo.getAssessments();
  final result = <Map<String, dynamic>>[];
  
  for (final a in assessments) {
    if (a.urgencyColor == null) continue; // Skip incomplete triages if any
    
    final patient = await repo.getPatientById(a.patientId);
    if (patient != null) {
      result.add({
        'assessment': a,
        'patient': patient,
      });
    }
  }
  return result;
});
