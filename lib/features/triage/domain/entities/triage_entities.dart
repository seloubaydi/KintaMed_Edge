import 'dart:typed_data';
import 'dart:convert';

class Patient {
  final String id;
  final String name;
  final int age;
  final String gender;
  final DateTime? dob;
  final String? emergencyPhone;
  final DateTime createdAt;

  Patient({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    this.dob,
    this.emergencyPhone,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'gender': gender,
      'dob': dob?.millisecondsSinceEpoch,
      'emergency_phone': emergencyPhone,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Patient.fromMap(Map<String, dynamic> map) {
    return Patient(
      id: map['id'],
      name: map['name'],
      age: map['age'],
      gender: map['gender'],
      dob: map['dob'] != null ? DateTime.fromMillisecondsSinceEpoch(map['dob']) : null,
      emergencyPhone: map['emergency_phone'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
    );
  }
}

class Assessment {
  final String id;
  final String patientId;
  final int? systolic;
  final int? diastolic;
  final int? heartRate;
  final double? temperature;
  final int? spo2;
  final String symptoms;
  final List<String>? allergies;
  final String? aiPrediction;
  final String? reasoning;
  final String? urgencyColor;
  final double? glucose;
  final double? height;
  final double? weight;
  final int? age;
  final String? gender;
  final List<Uint8List>? images;
  final DateTime timestamp;

  Assessment({
    required this.id,
    required this.patientId,
    this.systolic,
    this.diastolic,
    this.heartRate,
    this.temperature,
    this.spo2,
    required this.symptoms,
    this.allergies,
    this.aiPrediction,
    this.reasoning,
    this.urgencyColor,
    this.glucose,
    this.height,
    this.weight,
    this.age,
    this.gender,
    this.images,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patient_id': patientId,
      'systolic': systolic,
      'diastolic': diastolic,
      'heart_rate': heartRate,
      'temperature': temperature,
      'spo2': spo2,
      'symptoms': symptoms,
      'allergies': allergies?.join('|'),
      'ai_prediction': aiPrediction,
      'reasoning': reasoning,
      'urgency_color': urgencyColor,
      'glucose': glucose,
      'height': height,
      'weight': weight,
      'age': age,
      'gender': gender,
      'images': images != null ? images!.map((e) => base64Encode(e)).join('|') : null,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory Assessment.fromMap(Map<String, dynamic> map) {
    return Assessment(
      id: map['id'],
      patientId: map['patient_id'],
      systolic: map['systolic'],
      diastolic: map['diastolic'],
      heartRate: map['heart_rate'],
      temperature: map['temperature'],
      spo2: map['spo2'],
      symptoms: map['symptoms'],
      allergies: map['allergies'] != null ? (map['allergies'] as String).split('|') : null,
      aiPrediction: map['ai_prediction'],
      reasoning: map['reasoning'],
      urgencyColor: map['urgency_color'],
      glucose: map['glucose'],
      height: map['height'],
      weight: map['weight'],
      age: map['age'],
      gender: map['gender'],
      images: map['images'] != null ? (map['images'] as String).split('|').map((e) => base64Decode(e)).toList() : null,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    );
  }
  
  Assessment copyWith({
    String? aiPrediction,
    String? reasoning,
    String? urgencyColor,
    List<String>? allergies,
    double? glucose,
    double? height,
    double? weight,
    int? age,
    String? gender,
    // Pass true to explicitly set images to null (free raw image bytes).
    bool clearImages = false,
  }) {
    return Assessment(
      id: id,
      patientId: patientId,
      systolic: systolic,
      diastolic: diastolic,
      heartRate: heartRate,
      temperature: temperature,
      spo2: spo2,
      symptoms: symptoms,
      allergies: allergies ?? this.allergies,
      aiPrediction: aiPrediction ?? this.aiPrediction,
      reasoning: reasoning ?? this.reasoning,
      urgencyColor: urgencyColor ?? this.urgencyColor,
      glucose: glucose ?? this.glucose,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      images: clearImages ? null : this.images,
      timestamp: timestamp,
    );
  }
}
