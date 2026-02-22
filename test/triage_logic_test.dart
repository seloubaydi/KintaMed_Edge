import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:KintaMed_edge/core/ai/model_manager.dart';
import 'package:KintaMed_edge/features/triage/data/repositories/triage_repository.dart';
import 'package:KintaMed_edge/features/triage/domain/entities/triage_entities.dart';
import 'package:KintaMed_edge/features/triage/presentation/triage_controller.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:KintaMed_edge/features/settings/presentation/settings_controller.dart';
import 'package:KintaMed_edge/features/history/data/providers/history_providers.dart';

// Manual Mocks
class MockModelManager implements ModelManager {
  @override
  bool get isInitialized => true;

  @override
  bool get isMockMode => false;

  @override
  Stream<String> inferenceStream(String prompt, {List<Uint8List>? images}) async* {
    yield "This patient shows signs of hypertension.";
    yield " Recommended Triage: Yellow.";
  }
  
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void disposeModel() {}

  @override
  Future<void> init() async {}
  
  @override
  String? get currentModelPath => "model.bin";
  
  @override
  String formatChatMessage(String text, bool isUser, bool isBinary) => text;
}

class MockTriageRepository implements TriageRepository {
  final List<Assessment> savedAssessments = [];

  @override
  Future<void> saveAssessment(Assessment assessment) async {
    savedAssessments.add(assessment);
  }

  @override
  Future<List<Assessment>> getAssessmentsForPatient(String patientId) async {
    return [];
  }

  @override
  Future<List<Assessment>> getAssessments() async {
    return savedAssessments;
  }

  @override
  Future<void> savePatient(Patient patient) async {}

  @override
  Future<List<Patient>> getPatients() async => [];

  @override
  Future<Patient?> getPatientById(String id) async => null;

  @override
  Future<void> deleteAssessment(String id) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockModelManager mockModelManager;
  late MockTriageRepository mockRepo;

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    mockModelManager = MockModelManager();
    mockRepo = MockTriageRepository();
  });

  test('TriageController saves data before and after inference', () async {
    final container = ProviderContainer(
      overrides: [
        modelManagerProvider.overrideWithValue(mockModelManager),
        triageRepositoryProvider.overrideWithValue(mockRepo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        historyProvider.overrideWith((ref) => Future.value([])),
      ],
    );

    final assessment = Assessment(
      id: "1",
      patientId: "p1",
      systolic: 140,
      diastolic: 90,
      heartRate: 80,
      temperature: 37.0,
      spo2: 98,
      symptoms: "Headache",
      timestamp: DateTime.now(),
    );

    // Read the notifier
    final controller = container.read(triageControllerProvider.notifier);

    debugPrint("Test: Calling performTriage...");
    await controller.performTriage(assessment);
    debugPrint("Test: performTriage returned");

    final state = container.read(triageControllerProvider);
    debugPrint("Test: Final state: $state");
    
    expect(state.value, isNotNull);
    expect(state.value!.aiPrediction, contains("Yellow"));
    expect(state.value!.urgencyColor, "Yellow");

    // Verify Repository Calls
    // Should be saved twice: once initially (raw), once with result
    expect(mockRepo.savedAssessments.length, 2);
    expect(mockRepo.savedAssessments[0].aiPrediction, isNull); // First save
    expect(mockRepo.savedAssessments[1].aiPrediction, isNotNull); // Second save
  });
}
