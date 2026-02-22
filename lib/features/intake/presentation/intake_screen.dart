import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:uuid/uuid.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:io';
import '../../../core/localization/app_localizations.dart';
import '../../../core/ai/model_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../triage/domain/entities/triage_entities.dart';
import '../../triage/data/repositories/triage_repository.dart';
import '../../triage/presentation/triage_screen.dart';
import '../../settings/presentation/settings_controller.dart';

class IntakeScreen extends ConsumerStatefulWidget {
  final Patient? existingPatient;
  final Assessment? lastAssessment;

  const IntakeScreen({
    super.key, 
    this.existingPatient,
    this.lastAssessment,
  });

  @override
  ConsumerState<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends ConsumerState<IntakeScreen> with AutomaticKeepAliveClientMixin {
  final _formKeyPatient = GlobalKey<FormState>();
  final _formKeyClinical = GlobalKey<FormState>();
  // We won't use a FormKey for allergies as it's optional checkboxes, but we can if we add required fields later.
  
  final _pageController = PageController();
  int _currentPage = 0;

  // --- Step 1: Patient Identity ---
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  String? _selectedGender;
  DateTime? _selectedDOB;

  // --- Step 2: Allergies ---
  // Maps to store checkbox states
  final Map<String, bool> _medicationAllergies = {
    "No Known Drug Allergies (NKDA)": false,
    "Penicillin / Amoxicillin": false,
    "Sulfa Drugs": false,
    "NSAIDs (Aspirin, Ibuprofen, Naproxen)": false,
    "Contrast Dye / Iodine": false,
    "Latex": false,
  };
  final _otherMedsController = TextEditingController();

  final Map<String, bool> _foodAllergies = {
    "No Known Food Allergies": false,
    "Peanuts / Tree Nuts": false,
    "Shellfish / Fish": false,
    "Dairy / Milk": false,
    "Eggs": false,
    "Soy": false,
    "Wheat / Gluten": false,
  };
  final _otherFoodController = TextEditingController();

  final Map<String, bool> _envAllergies = {
    "Seasonal / Pollen / Mold": false,
    "Pet Dander (Cats/Dogs)": false,
    "Insect Stings (Bees/Wasps)": false,
    "Fragrances / Cosmetics": false,
  };
  final _otherEnvController = TextEditingController();


  // --- Step 3: Clinical Data ---
  final _symptomsController = TextEditingController();
  final _tempController = TextEditingController();
  final _hrController = TextEditingController();
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _glucoseController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

  // Image Support
  final List<Uint8List> _capturedImages = [];
  final ImagePicker _picker = ImagePicker();


  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    
    // Pre-fill data if existing patient provided
    if (widget.existingPatient != null) {
      final names = widget.existingPatient!.name.split(' ');
      if (names.isNotEmpty) _firstNameController.text = names[0];
      if (names.length > 1) _lastNameController.text = names.sublist(1).join(' ');
      _selectedGender = widget.existingPatient!.gender;
      _selectedDOB = widget.existingPatient!.dob;
      _emergencyContactController.text = widget.existingPatient!.emergencyPhone ?? "";
    }
    
    if (widget.lastAssessment != null) {
      final allergies = widget.lastAssessment!.allergies ?? [];
      for (final a in allergies) {
        if (a.startsWith("Medication: ")) {
          final med = a.replaceFirst("Medication: ", "");
          if (_medicationAllergies.containsKey(med)) {
            _medicationAllergies[med] = true;
          } else {
            _otherMedsController.text += (_otherMedsController.text.isEmpty ? "" : ", ") + med;
          }
        } else if (a.startsWith("Food: ")) {
          final food = a.replaceFirst("Food: ", "");
          if (_foodAllergies.containsKey(food)) {
            _foodAllergies[food] = true;
          } else {
            _otherFoodController.text += (_otherFoodController.text.isEmpty ? "" : ", ") + food;
          }
        } else if (a.startsWith("Env: ")) {
          final env = a.replaceFirst("Env: ", "");
          if (_envAllergies.containsKey(env)) {
            _envAllergies[env] = true;
          } else {
            _otherEnvController.text += (_otherEnvController.text.isEmpty ? "" : ", ") + env;
          }
        }
      }
    }
  }


  Future<void> _pickImage(ImageSource source) async {
    try {
      if ((Platform.isLinux || Platform.isWindows) && source == ImageSource.gallery) {
        // Use file_selector for gallery on Linux to avoid crashes
        const XTypeGroup typeGroup = XTypeGroup(
          label: 'images',
          extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
        );
        final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
        
        if (file != null) {
          final bytes = await file.readAsBytes();
          setState(() {
            _capturedImages.add(bytes);
          });
        }
        return;
      }

      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
        requestFullMetadata: false, 
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _capturedImages.add(bytes);
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to select image: $e")),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _capturedImages.removeAt(index);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emergencyContactController.dispose();
    _symptomsController.dispose();
    _tempController.dispose();
    _hrController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _spo2Controller.dispose();
    _glucoseController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _otherMedsController.dispose();
    _otherFoodController.dispose();
    _otherEnvController.dispose();
    super.dispose();
  }

  void _nextPage() {
    // Validate current page
    if (_currentPage == 0) {
      if (!_formKeyPatient.currentState!.validate()) return;
    } else if (_currentPage == 2) { 
      // Clinical is now step 2 (index 2)
      if (!_formKeyClinical.currentState!.validate()) return;
    }
    // Allergies (index 1) doesn't have required validation per user req

    final settings = ref.read(aiSettingsProvider);
    final bool hasMultimodal = settings.isModelDownloaded;
    final int lastPage = hasMultimodal ? 3 : 2;

    if (_currentPage >= lastPage) {
      _submit();
      return;
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentPage++);
  }

  void _prevPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
     setState(() => _currentPage--);
  }

  List<String> _collectAllergies() {
    final List<String> allergies = [];
    _medicationAllergies.forEach((key, value) {
      if(value) allergies.add("Medication: $key");
    });
    if(_otherMedsController.text.isNotEmpty) allergies.add("Medication: ${_otherMedsController.text}");

    _foodAllergies.forEach((key, value) {
      if(value) allergies.add("Food: $key");
    });
    if(_otherFoodController.text.isNotEmpty) allergies.add("Food: ${_otherFoodController.text}");

    _envAllergies.forEach((key, value) {
       if(value) allergies.add("Env: $key");
    });
    if(_otherEnvController.text.isNotEmpty) allergies.add("Env: ${_otherEnvController.text}");

    return allergies;
  }

  int _calculateAge(DateTime birthDate) {
    DateTime today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  Future<void> _submit() async {
    int? age;
    if (_selectedDOB != null) {
      age = _calculateAge(_selectedDOB!);
    }

    // Create Assessment Object
    final assessment = Assessment(
      id: const Uuid().v4(),
      patientId: widget.existingPatient?.id ?? const Uuid().v4(),
      systolic: int.tryParse(_systolicController.text.trim()),
      diastolic: int.tryParse(_diastolicController.text.trim()),
      heartRate: int.tryParse(_hrController.text.trim()),
      temperature: double.tryParse(_tempController.text.trim()),
      spo2: int.tryParse(_spo2Controller.text.trim()),
      glucose: double.tryParse(_glucoseController.text.trim()),
      height: double.tryParse(_heightController.text.trim()),
      weight: double.tryParse(_weightController.text.trim()),
      age: age,
      gender: _selectedGender,
      images: _capturedImages.isNotEmpty ? List.from(_capturedImages) : null,
      symptoms: _symptomsController.text.isNotEmpty 
          ? _symptomsController.text 
          : "No specific symptoms reported",
      allergies: _collectAllergies(),
      timestamp: DateTime.now(),
    );

    // Save or Update Patient details
    final patientToSave = Patient(
      id: widget.existingPatient?.id ?? assessment.patientId,
      name: "${_firstNameController.text} ${_lastNameController.text}".trim(),
      age: age ?? 0,
      gender: _selectedGender ?? "Unknown",
      dob: _selectedDOB,
      emergencyPhone: _emergencyContactController.text,
      createdAt: widget.existingPatient?.createdAt ?? DateTime.now(),
    );
    await ref.read(triageRepositoryProvider).savePatient(patientToSave);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TriageScreen(assessment: assessment),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // Use the AppTheme colors
    final bgColor = AppTheme.background;
    final primaryColor = AppTheme.primary;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent, 
        automaticallyImplyLeading: false, 
        elevation: 0,
        title: Row(
          children: [
             Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.medical_services_rounded, color: AppTheme.background),
              ),
            const Gap(12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KintaMed Edge',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                Text(
                  l10n.translate("clinical_data_collection"),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
           IconButton(
             onPressed: () {}, 
             icon: const Icon(Icons.save_outlined, color: AppTheme.primary),
           ),
           IconButton(
             onPressed: () {}, 
             icon: const Icon(Icons.help_outline, color: AppTheme.primary),
           ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), 
                children: [
                  _KeepAlivePage(child: _buildStep1Identity()),
                  _KeepAlivePage(child: _buildStep2Allergies()),
                  _KeepAlivePage(child: _buildStep3Clinical()),
                  // Requirement: Step 4 (Visual Probe) is available if the multimodal model is downloaded.
                  if (ref.watch(aiSettingsProvider).isModelDownloaded)
                    _KeepAlivePage(child: _buildStep4VisualProbe()),
                ],
              ),
            ),
            
            // Navigation Bottom Bar
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage > 0)
                    TextButton.icon(
                      onPressed: _prevPage,
                      icon: const Icon(Icons.arrow_back, color: Colors.white70),
                      label: Text(l10n.translate("back"), style: GoogleFonts.outfit(color: Colors.white70)),
                    )
                  else
                    TextButton(
                       onPressed: () => Navigator.pop(context),
                       child: Text(l10n.translate("cancel"), style: GoogleFonts.outfit(color: Colors.redAccent)),
                    ),
  
                  Builder(
                    builder: (context) {
                      final settings = ref.watch(aiSettingsProvider);
                      final bool hasMultimodal = settings.isModelDownloaded;
                      final int lastPageIndex = hasMultimodal ? 3 : 2;
  
                      if (_currentPage < lastPageIndex) {
                        return ElevatedButton.icon(
                          onPressed: _nextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: AppTheme.background,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(l10n.translate("next_step"), style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                        );
                      } else {
                        return ElevatedButton.icon(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success, 
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text("Submit Intake", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                        );
                      }
                    }
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Step 1 Widgets ---
  Widget _buildStep1Identity() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKeyPatient,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.translate("step_1_patient_identity"), style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const Gap(24),
            
            Row(
              children: [
                Expanded(child: _buildTextField(l10n.translate("first_name"), _firstNameController, hint: "Jane")),
                const Gap(16),
                Expanded(child: _buildTextField(l10n.translate("last_name"), _lastNameController, hint: "Doe")),
              ],
            ),
            const Gap(24),
            Row(
              children: [
                Expanded(child: _buildDropdown(l10n.translate("biological_sex"), ["Male", "Female", "Other"])),
                const Gap(16),
                Expanded(child: _buildDatePicker(l10n.translate("date_of_birth"))),
              ],
            ),
            const Gap(24),
            _buildTextField(l10n.translate("emergency_contact_phone"), _emergencyContactController, hint: "+1 ...", type: TextInputType.phone),
          ],
        ),
      ),
    ).animate().fadeIn();
  }

  // --- Step 2 Widgets (Allergies) ---
  Widget _buildStep2Allergies() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.translate("step_2_allergies_sensitivities"), style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const Gap(8),
          Text(
            l10n.translate("please_check_all_that_apply_provide_details_if_selected"),
            style: GoogleFonts.inter(color: Colors.white70),
          ),
          const Gap(24),

          _buildChecklistSection(l10n.translate("medication_allergies"), _medicationAllergies, _otherMedsController),
          const Gap(24),
          _buildChecklistSection(l10n.translate("food_allergies"), _foodAllergies, _otherFoodController),
          const Gap(24),
          _buildChecklistSection(l10n.translate("environmental_other"), _envAllergies, _otherEnvController),
          
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildChecklistSection(String title, Map<String, bool> items, TextEditingController otherController) {
     final l10n = AppLocalizations.of(context);
    return Container(
    
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
          const Gap(12),
          ...items.keys.map((key) {
             return CheckboxListTile(
               contentPadding: EdgeInsets.zero,
               title: Text(key, style: const TextStyle(color: Colors.white)),
               value: items[key],
               activeColor: AppTheme.primary,
               checkColor: AppTheme.background,
               controlAffinity: ListTileControlAffinity.leading,
               onChanged: (val) {
                 setState(() {
                   items[key] = val ?? false;
                   // Logic for Exclusive "No Known ..." checkboxes could go here (uncheck others if this is checked)
                   if (key.startsWith("No Known") && val == true) {
                      // Uncheck everything else in this group
                      items.forEach((k, v) {
                        if (k != key) items[k] = false;
                      });
                      otherController.clear();
                   } else if (!key.startsWith("No Known") && val == true) {
                      // Uncheck "No Known" if a specific one is checked
                      final noKnownKey = items.keys.firstWhere((k) => k.startsWith("No Known"), orElse: () => "");
                      if (noKnownKey.isNotEmpty) items[noKnownKey] = false;
                   }
                 });
               }
             );
          }).toList(),
          const Gap(8),
          _buildTextField(l10n.translate("other"), otherController, hint: "Specify other...", type: TextInputType.text),
        ],
      ),
    );
  }


  // --- Step 3 Widgets (Clinical) ---
  Widget _buildStep3Clinical() {
      final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKeyClinical,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.translate("step_3_vital_signs"), style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const Gap(24),

            Text(l10n.translate("reason_for_consultation"), style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
            const Gap(8),
            TextFormField(
              controller: _symptomsController,
              maxLines: 4,
              cursorColor: AppTheme.primary,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surface,
                hintText: l10n.translate("describe_the_patients_main_complaint"),
                hintStyle: const TextStyle(color: Colors.white30),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
              ),
              validator: (val) => val == null || val.isEmpty ? l10n.translate("please_enter_a_reason") : null,
            ),
            const Gap(24),

            Row(
              children: [
                 Expanded(child: _buildTextField(l10n.translate("temperature"), _tempController, type: const TextInputType.numberWithOptions(decimal: true), hint: "36.5")),
                 const Gap(16),
                 Expanded(child: _buildTextField(l10n.translate("heart_rate"), _hrController, type: TextInputType.number, hint: "72")),
              ],
            ),
            const Gap(16),
             Row(
              children: [
                 Expanded(child: _buildTextField(l10n.translate("systolic"), _systolicController, type: TextInputType.number, hint: "120")),
                 const Gap(16),
                 Expanded(child: _buildTextField(l10n.translate("diastolic"), _diastolicController, type: TextInputType.number, hint: "80")),
              ],
            ),
            const Gap(16),
             Row(
              children: [
                 Expanded(child: _buildTextField(l10n.translate("spo2"), _spo2Controller, type: TextInputType.number, hint: "98")),
                 const Gap(16),
                 Expanded(child: _buildTextField(l10n.translate("glucose"), _glucoseController, type: const TextInputType.numberWithOptions(decimal: true), hint: "90", isBold: true)), 
              ],
            ),
            const Gap(16),
            Row(
              children: [
                 Expanded(child: _buildTextField(l10n.translate("height"), _heightController, type: TextInputType.number, hint: "170")),
                 const Gap(16),
                 Expanded(child: _buildTextField(l10n.translate("weight"), _weightController, type: TextInputType.number, hint: "70")), 
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn();
  }

  // --- Step 4 Widgets (Visual Probe) ---
  Widget _buildStep4VisualProbe() {
      final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.translate("step_4_visual_probe"), style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const Gap(8),
          Text(
            l10n.translate("take_a_photo"),
            style: GoogleFonts.inter(color: Colors.white70),
          ),
          const Gap(32),

          Center(
            child: Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: _capturedImages.isEmpty
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 64, color: AppTheme.primary.withOpacity(0.5)),
                        const Gap(16),
                        Text( l10n.translate("no_images_captured"), style: GoogleFonts.outfit(color: Colors.white38)),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      scrollDirection: Axis.horizontal,
                      itemCount: _capturedImages.length,
                      separatorBuilder: (_, __) => const Gap(16),
                      itemBuilder: (context, index) {
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                _capturedImages[index],
                                width: 200,
                                height: 260,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: CircleAvatar(
                                backgroundColor: Colors.black54,
                                radius: 18,
                                child: IconButton(
                                  icon: const Icon(Icons.close, size: 16, color: Colors.white),
                                  onPressed: () => _removeImage(index),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
          const Gap(24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera),
                label: Text(l10n.translate("camera")),
              ),
              const Gap(16),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
                icon: const Icon(Icons.photo_library),
                label: Text(l10n.translate("gallery")),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  // --- Helpers ---
  Widget _buildTextField(String label, TextEditingController controller, {TextInputType type = TextInputType.text, String? hint, bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.primary, fontWeight: isBold ? FontWeight.bold : FontWeight.w600)),
        const Gap(8),
        TextFormField(
          controller: controller,
          keyboardType: type,
          cursorColor: AppTheme.primary,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.surface,
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white30),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
          ),
          validator: (val) {
             // Step 1 check (Name/Identity)
             if (controller == _firstNameController || controller == _lastNameController) {
                if (val == null || val.isEmpty) return "Required";
                return null;
             }

             // Clinical Range Validation (Optional fields, but if provided must be logical)
             if (val == null || val.isEmpty) return null;

             final clinicalControllers = [
               _tempController, _hrController, _systolicController, 
               _diastolicController, _spo2Controller, _glucoseController,
               _heightController, _weightController
             ];

             if (!clinicalControllers.contains(controller)) return null;

             final numVal = double.tryParse(val.trim());
             if (numVal == null) return "Invalid number";

             if (controller == _tempController) {
               if (numVal < 30.0 || numVal > 45.0) return "Range: 30-45°C";
             } else if (controller == _hrController) {
               if (numVal < 30 || numVal > 250) return "Range: 30-250 bpm";
             } else if (controller == _systolicController) {
               if (numVal < 50 || numVal > 250) return "Range: 50-250";
             } else if (controller == _diastolicController) {
               if (numVal < 30 || numVal > 150) return "Range: 30-150";
             } else if (controller == _spo2Controller) {
               if (numVal < 50 || numVal > 100) return "Range: 50-100%";
             } else if (controller == _glucoseController) {
               if (numVal < 10 || numVal > 1000) return "Range: 10-1000";
             }

             return null;
          },
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        const Gap(8),
        DropdownButtonFormField<String>(
          value: _selectedGender,
          dropdownColor: AppTheme.surface,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
             focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
          ),
          hint: const Text("Select...", style: TextStyle(color: Colors.white30)),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (val) => setState(() => _selectedGender = val),
           validator: (val) {
             if (val == null || val.isEmpty) return "Required";
             return null;
          },
        ),
      ],
    );
  }

  Widget _buildDatePicker(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        const Gap(8),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final res = await showDatePicker(
              context: context,
              initialDate: _selectedDOB ?? DateTime(1990),
              firstDate: DateTime(1900),
              lastDate: now,
              builder: (ctx, child) {
                return Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(
                       primary: AppTheme.primary,
                       onPrimary: AppTheme.background,
                       surface: AppTheme.surface,
                       onSurface: Colors.white,
                    ),
                  ),
                  child: child!,
                );
              }
            );
            if (res != null) {
              setState(() => _selectedDOB = res);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedDOB != null 
                    ? "${_selectedDOB!.year}-${_selectedDOB!.month.toString().padLeft(2,'0')}-${_selectedDOB!.day.toString().padLeft(2,'0')}"
                    : "Select Date",
                  style: TextStyle(color: _selectedDOB != null ? Colors.white : Colors.white30),
                ),
                const Icon(Icons.calendar_today, color: AppTheme.primary, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Wrapper to keep state alive in PageView
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});
  @override
  _KeepAlivePageState createState() => _KeepAlivePageState();
}
class _KeepAlivePageState extends State<_KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
