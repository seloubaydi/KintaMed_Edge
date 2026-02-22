import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

final databaseServiceProvider = Provider<DatabaseService>((ref) => DatabaseService());

class DatabaseService {
  static const String _dbName = 'KintaMed_edge.db';
  static const String _dbPassword = 'super_secure_medical_password_123!'; 
  
  sqflite.Database? _database;

  Future<sqflite.Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<sqflite.Database> _initDatabase() async {
    // 1. Web Support
    if (kIsWeb) {
      sqflite.databaseFactory = databaseFactoryFfiWeb;
      return await sqflite.openDatabase(
        _dbName,
        version: 6,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }

    // 2. Desktop Support (Linux/Windows/MacOS)
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      sqflite.databaseFactory = databaseFactoryFfi; 
      
      final dbPath = await sqflite.getDatabasesPath();
      final path = join(dbPath, _dbName);
      
      return await sqflite.openDatabase(
        path,
        version: 6,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
    
    // 3. Mobile Support (Encrypted)
    final dbPath = await sqlcipher.getDatabasesPath();
    final path = join(dbPath, _dbName);
    
    return await sqlcipher.openDatabase(
      path,
      password: _dbPassword,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(sqflite.Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE assessments ADD COLUMN allergies TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE assessments ADD COLUMN glucose REAL');
      await db.execute('ALTER TABLE assessments ADD COLUMN height REAL');
      await db.execute('ALTER TABLE assessments ADD COLUMN weight REAL');
      await db.execute('ALTER TABLE assessments ADD COLUMN images TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE assessments ADD COLUMN age INTEGER');
      await db.execute('ALTER TABLE assessments ADD COLUMN gender TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE patients ADD COLUMN dob INTEGER');
      await db.execute('ALTER TABLE patients ADD COLUMN emergency_phone TEXT');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE assessments ADD COLUMN reasoning TEXT');
    }
  }

  Future<void> _onCreate(sqflite.Database db, int version) async {
    await db.execute('''
      CREATE TABLE patients (
        id TEXT PRIMARY KEY,
        name TEXT,
        age INTEGER,
        gender TEXT,
        dob INTEGER,
        emergency_phone TEXT,
        created_at INTEGER
      )
    ''');
    
    await db.execute('''
      CREATE TABLE assessments (
        id TEXT PRIMARY KEY,
        patient_id TEXT,
        systolic INTEGER,
        diastolic INTEGER,
        heart_rate INTEGER,
        temperature REAL,
        spo2 INTEGER,
        symptoms TEXT,
        allergies TEXT,
        ai_prediction TEXT,
        reasoning TEXT,
        urgency_color TEXT,
        glucose REAL,
        height REAL,
        weight REAL,
        age INTEGER,
        gender TEXT,
        images TEXT,
        timestamp INTEGER,
        is_synced INTEGER DEFAULT 0
      )
    ''');
  }
}
