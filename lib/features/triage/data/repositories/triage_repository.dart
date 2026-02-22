import 'package:sqflite/sqflite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/database_service.dart';
import '../../domain/entities/triage_entities.dart';

final triageRepositoryProvider = Provider<TriageRepository>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return TriageRepository(dbService);
});

class TriageRepository {
  final DatabaseService _dbService;

  TriageRepository(this._dbService);

  Future<void> savePatient(Patient patient) async {
    final db = await _dbService.database;
    await db.insert(
      'patients',
      patient.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, 
    );
  }

  Future<List<Patient>> getPatients() async {
    final db = await _dbService.database;
    final maps = await db.query('patients', orderBy: 'created_at DESC');
    return maps.map((e) => Patient.fromMap(e)).toList();
  }

  Future<void> saveAssessment(Assessment assessment) async {
    final db = await _dbService.database;
    await db.insert(
      'assessments',
      assessment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Assessment>> getAssessments() async {
    final db = await _dbService.database;
    final maps = await db.query('assessments', orderBy: 'timestamp DESC');
    return maps.map((e) => Assessment.fromMap(e)).toList();
  }
  
  Future<List<Assessment>> getAssessmentsForPatient(String patientId) async {
    final db = await _dbService.database;
    final maps = await db.query(
      'assessments', 
      where: 'patient_id = ?', 
      whereArgs: [patientId],
      orderBy: 'timestamp DESC'
    );
    return maps.map((e) => Assessment.fromMap(e)).toList();
  }

  Future<Patient?> getPatientById(String id) async {
    final db = await _dbService.database;
    final maps = await db.query(
      'patients',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Patient.fromMap(maps.first);
    }
    return null;
  }

  Future<void> deleteAssessment(String id) async {
    final db = await _dbService.database;
    await db.delete(
      'assessments',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
