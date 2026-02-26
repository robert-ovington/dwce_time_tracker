/// Delivery Screen
/// 
/// Screen for recording waste deliveries with GPS tracking, photos, and signatures

import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import '../modules/deliveries/delivery_service.dart';
import '../modules/deliveries/delivery_photo_helper.dart';
import '../modules/auth/auth_service.dart';
import '../modules/errors/error_log_service.dart';
import '../modules/users/user_service.dart';
import '../config/supabase_config.dart';
import '../modules/asset_check/asset_check_service.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // User data
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _userSetup; // Store users_setup for display_name

  // Date & Time
  DateTime _selectedDate = DateTime.now();
  String _time = '07:30'; // Store time as string in 24-hour format (HH:mm)

  // Dropdowns
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _largePlant = [];
  List<Map<String, dynamic>> _wasteFacilities = [];
  List<Map<String, dynamic>> _materials = [];

  // Project maps for lookups
  Map<String, Map<String, dynamic>> _projectMapById = {};
  Map<String, Map<String, dynamic>> _projectMapByName = {};

  String? _selectedFromProjectId;
  String? _selectedFromProjectName;
  bool _fromProjectSelected = false;
  String _fromProjectFilter = '';
  int _fromProjectFilterResetCounter = 0;

  String? _selectedToProjectId;
  String? _selectedToProjectName;
  bool _toProjectSelected = false;
  String _toProjectFilter = '';
  int _toProjectFilterResetCounter = 0;

  String? _selectedLargePlantId;
  String? _selectedMaterialId;
  String? _selectedFacilityId;

  // Material details
  final TextEditingController _ewcCodeController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _wasteDescriptionController = TextEditingController();

  // GPS
  double? _collectedLat;
  double? _collectedLng;
  double? _deliveredLat;
  double? _deliveredLng;
  bool _isCapturingCollectedGps = false;
  bool _isCapturingDeliveredGps = false;

  // Photos
  XFile? _docketPhoto;
  String? _docketPhotoUrl;

  // Signature
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  String? _receiverSignatureUrl;
  bool _hasSignature = false;

  // Checkbox
  bool _isReinstatement = false;

  @override
  void initState() {
    super.initState();
    // Set default time to current time rounded to 15 minutes
    final now = DateTime.now();
    final roundedMinutes = ((now.minute / 15).round() * 15) % 60;
    final roundedTime = DateTime(now.year, now.month, now.day, now.hour, roundedMinutes);
    _time = DateFormat('HH:mm').format(roundedTime);
    _loadCurrentUser();
    _loadData();
  }

  @override
  void dispose() {
    _ewcCodeController.dispose();
    _quantityController.dispose();
    _wasteDescriptionController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = AuthService.getCurrentUser();
      if (user != null) {
        setState(() {
          _currentUser = {
            'id': user.id,
            'email': user.email,
          };
        });
        await _loadUserData();
      }
    } catch (e) {
      print('Error loading current user: $e');
    }
  }

  Future<void> _loadUserData() async {
    try {
      if (_currentUser == null) return;
      
      // Load users_data
      final userData = await UserService.getCurrentUserData();
      if (userData != null) {
        setState(() {
          _userData = userData;
        });
      }
      
      // Load users_setup separately
      final userSetup = await UserService.getCurrentUserSetup();
      if (userSetup != null) {
        setState(() {
          _userSetup = userSetup;
        });
      }
      
      // Auto-select vehicle from user's fleet_1 if available
      _autoSelectVehicle();
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  /// Auto-select vehicle from user's stock_location (vehicle id) in users_data if set and present in the vehicle list
  void _autoSelectVehicle() {
    if (_userData == null || _largePlant.isEmpty) return;

    final stockLocation = _userData!['stock_location']?.toString()?.trim();
    if (stockLocation == null || stockLocation.isEmpty) return;

    final exists = _largePlant.any((plant) => plant['id']?.toString() == stockLocation);
    if (exists) {
      setState(() => _selectedLargePlantId = stockLocation);
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        DeliveryService.getProjects(),
        DeliveryService.getLargePlant(),
        DeliveryService.getWasteFacilities(),
        DeliveryService.getMaterials(),
      ]);

      final projects = results[0] as List<Map<String, dynamic>>;
      final projectMapById = <String, Map<String, dynamic>>{};
      final projectMapByName = <String, Map<String, dynamic>>{};
      for (final project in projects) {
        final id = project['id']?.toString();
        final name = project['project_name']?.toString() ?? '';
        if (id != null) {
          projectMapById[id] = project;
        }
        if (name.isNotEmpty) {
          projectMapByName[name] = project;
        }
      }

      // Sort vehicles by plant_no (simple alphabetical/numerical sort on first character)
      final largePlant = (results[1] as List<Map<String, dynamic>>).toList();
      largePlant.sort((a, b) {
        final plantNoA = a['plant_no']?.toString() ?? '';
        final plantNoB = b['plant_no']?.toString() ?? '';
        return plantNoA.compareTo(plantNoB);
      });

      final wasteFacilities = results[2] as List<Map<String, dynamic>>;
      print('✅ Delivery Screen loaded ${wasteFacilities.length} waste facilities');
      if (wasteFacilities.isNotEmpty) {
        print('   First facility: ${wasteFacilities.first['facility_name']}');
      } else {
        print('   ⚠️ No facilities loaded - check database and RLS policies');
      }
      
      setState(() {
        _projects = projects;
        _largePlant = largePlant;
        _wasteFacilities = wasteFacilities;
        _materials = results[3] as List<Map<String, dynamic>>;
        _projectMapById = projectMapById;
        _projectMapByName = projectMapByName;
        _isLoading = false;
      });
      
      // Auto-select vehicle from user's fleet_1 if available
      _autoSelectVehicle();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Delivery Screen - Load Data',
        type: 'Database',
        description: 'Failed to load data: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Generate time options (15-minute intervals)
  List<String> _generateTimeOptions() {
    final times = <String>[];
    for (int hour = 0; hour < 24; hour++) {
      for (int minute = 0; minute < 60; minute += 15) {
        final timeString = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        times.add(timeString);
      }
    }
    return times;
  }

  /// Convert 24-hour time to 12-hour format with AM/PM
  String _convertTo12Hour(String time24) {
    if (time24.isEmpty) return '';
    final parts = time24.split(':');
    if (parts.length != 2) return time24;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  DateTime _getMinDate(DateTime currentDate) {
    // Allow dates from 30 days ago
    return currentDate.subtract(const Duration(days: 30));
  }

  Future<void> _captureCollectedGps() async {
    setState(() {
      _isCapturingCollectedGps = true;
    });

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _collectedLat = position.latitude;
        _collectedLng = position.longitude;
        _isCapturingCollectedGps = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Collected GPS location captured'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isCapturingCollectedGps = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture GPS: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _captureDeliveredGps() async {
    setState(() {
      _isCapturingDeliveredGps = true;
    });

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _deliveredLat = position.latitude;
        _deliveredLng = position.longitude;
        _isCapturingDeliveredGps = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivered GPS location captured'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isCapturingDeliveredGps = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture GPS: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickDocketPhoto() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text('Camera'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('Gallery'),
          ),
        ],
      ),
    );

    if (source != null) {
      final image = await DeliveryPhotoHelper.pickImage(source: source);
      if (image != null && mounted) {
        setState(() {
          _docketPhoto = image;
        });
      }
    }
  }

  Future<void> _showSignatureDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Receiver Signature'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: Signature(
            controller: _signatureController,
            backgroundColor: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _signatureController.clear();
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!_signatureController.isEmpty) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a signature'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && !_signatureController.isEmpty) {
      setState(() {
        _hasSignature = true;
      });
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedLargePlantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a vehicle'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedMaterialId == null && _ewcCodeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a material or enter EWC code'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final user = AuthService.getCurrentUser();
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Generate temporary ID for photo uploads
      final tempId = DateTime.now().millisecondsSinceEpoch.toString();

      // Upload docket photo if selected
      String? docketPhotoUrl;
      if (_docketPhoto != null) {
        try {
          docketPhotoUrl = await DeliveryPhotoHelper.uploadDocketPhoto(
            imageFile: _docketPhoto!,
            deliveryId: tempId,
          );
        } catch (e) {
          print('⚠️ Failed to upload docket photo: $e');
          // Continue without photo
        }
      }

      // Export and upload signature if provided
      String? receiverSignatureUrl;
      if (_hasSignature && !_signatureController.isEmpty) {
        try {
          final signatureBytes = await _signatureController.toPngBytes();
          if (signatureBytes != null) {
            // Create temporary file for signature
            final tempDir = Directory.systemTemp;
            final tempFile = File('${tempDir.path}/signature_$tempId.png');
            await tempFile.writeAsBytes(signatureBytes);
            
            final signatureXFile = XFile(tempFile.path);
            receiverSignatureUrl = await DeliveryPhotoHelper.uploadSignature(
              imageFile: signatureXFile,
              deliveryId: tempId,
            );
            
            // Clean up temp file
            await tempFile.delete();
          }
        } catch (e) {
          print('⚠️ Failed to upload signature: $e');
          // Continue without signature
        }
      }

      // Build delivery data
      final deliveryData = <String, dynamic>{
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'time': _time, // Save time field
        'user_auth_id': user.id,
        'large_plant_id': _selectedLargePlantId,
        if (_selectedFromProjectId != null) 'from_project_id': _selectedFromProjectId,
        if (_selectedToProjectId != null) 'to_project_id': _selectedToProjectId,
        if (_selectedMaterialId != null) 'material_id': _selectedMaterialId,
        if (_ewcCodeController.text.isNotEmpty) 'ewc_code': _ewcCodeController.text.trim(),
        if (_quantityController.text.isNotEmpty) 
          'quantity': double.tryParse(_quantityController.text.trim()),
        if (_wasteDescriptionController.text.isNotEmpty) 
          'waste_description': _wasteDescriptionController.text.trim(),
        if (docketPhotoUrl != null) 'docket_photo_url': docketPhotoUrl,
        if (_collectedLat != null) 'collected_gps_lat': _collectedLat,
        if (_collectedLng != null) 'collected_gps_lng': _collectedLng,
        if (_deliveredLat != null) 'delivered_gps_lat': _deliveredLat,
        if (_deliveredLng != null) 'delivered_gps_lng': _deliveredLng,
        if (receiverSignatureUrl != null) 'receiver_signature': receiverSignatureUrl,
        if (_selectedFacilityId != null) 'facility_id': _selectedFacilityId,
        if (_hasSignature && receiverSignatureUrl != null) 
          'receiver_signed_at': DateTime.now().toIso8601String(),
        'is_reinstatement': _isReinstatement,
        'is_active': true,
        'synced': true,
        'offline_created': false,
      };

      // Create delivery record
      await DeliveryService.createDelivery(deliveryData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery recorded successfully'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Reset form
        _resetForm();
      }
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Delivery Screen - Save',
        type: 'Database',
        description: 'Failed to save delivery: $e',
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save delivery: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _resetForm() {
    setState(() {
      _selectedFromProjectId = null;
      _selectedFromProjectName = null;
      _fromProjectSelected = false;
      _fromProjectFilter = '';
      _fromProjectFilterResetCounter++;
      _selectedToProjectId = null;
      _selectedToProjectName = null;
      _toProjectSelected = false;
      _toProjectFilter = '';
      _toProjectFilterResetCounter++;
      _selectedLargePlantId = null;
      _selectedMaterialId = null;
      _selectedFacilityId = null;
      _ewcCodeController.clear();
      _quantityController.clear();
      _wasteDescriptionController.clear();
      _collectedLat = null;
      _collectedLng = null;
      _deliveredLat = null;
      _deliveredLng = null;
      _docketPhoto = null;
      _docketPhotoUrl = null;
      _signatureController.clear();
      _hasSignature = false;
      _isReinstatement = false;
      // Reset time to current time rounded to 15 minutes
      final now = DateTime.now();
      final roundedMinutes = ((now.minute / 15).round() * 15) % 60;
      final roundedTime = DateTime(now.year, now.month, now.day, now.hour, roundedMinutes);
      _time = DateFormat('HH:mm').format(roundedTime);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0081FB),
        title: const Text(
          'Waste Delivery',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        foregroundColor: Colors.black,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: Container(
            height: 4.0,
            color: const Color(0xFFFEFE00),
          ),
        ),
        actions: const [ScreenInfoIcon(screenName: 'delivery_screen.dart')],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Section 1: Employee Details
                    _buildEmployeeDetailsSection(),
                    const SizedBox(height: 16),
                    
                    // Section 2: Collection
                    _buildCollectionSection(),
                    const SizedBox(height: 16),
                    
                    // Section 3: Materials
                    _buildMaterialsSection(),
                    const SizedBox(height: 16),
                    
                    // Section 4: Delivery
                    _buildDeliverySection(),
                    const SizedBox(height: 24),
                    
                    // Save Button
                    ElevatedButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0081FB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save Delivery'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEmployeeDetailsSection() {
    // Get user display name with priority: users_setup.display_name > users_data.display_name > auth.users.email
    String currentUserDisplay = 'Unknown';
    
    // Priority 1: Try display_name from users_setup (format: "Surname, Forename")
    if (_userSetup != null && _userSetup!['display_name'] != null) {
      final displayName = _userSetup!['display_name'].toString();
      if (displayName.isNotEmpty) {
        if (displayName.contains(',')) {
          final parts = displayName.split(',');
          if (parts.length == 2) {
            currentUserDisplay = '${parts[1].trim()} ${parts[0].trim()}';
          } else {
            currentUserDisplay = displayName;
          }
        } else {
          currentUserDisplay = displayName;
        }
      }
    }
    
    // Priority 2: Try display_name from users_data table
    if (currentUserDisplay == 'Unknown' && _userData != null && _userData!['display_name'] != null) {
      final displayName = _userData!['display_name'].toString();
      if (displayName.isNotEmpty) {
        if (displayName.contains(',')) {
          final parts = displayName.split(',');
          if (parts.length == 2) {
            currentUserDisplay = '${parts[1].trim()} ${parts[0].trim()}';
          } else {
            currentUserDisplay = displayName;
          }
        } else {
          currentUserDisplay = displayName;
        }
      }
    }
    
    // Priority 3: Fallback to auth.users.email
    if (currentUserDisplay == 'Unknown' && _currentUser != null) {
      currentUserDisplay = (_currentUser!['email'] as String?) ?? 'Unknown';
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF005AB0), width: 2),
                ),
              ),
              child: const Center(
                child: Text(
                  'Employee Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Name
                  Row(
                    children: [
                      const Icon(Icons.person, color: Color(0xFF0081FB)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentUserDisplay,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Date (formatted same as timesheet)
                  Builder(
                    builder: (context) {
                      final currentDate = DateTime.now();
                      final selectedDate = _selectedDate;
                      final maxDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
                      final minDate = _getMinDate(currentDate);
                      final isCurrentDate = selectedDate.year == maxDate.year &&
                                          selectedDate.month == maxDate.month &&
                                          selectedDate.day == maxDate.day;
                      final isPastDate = selectedDate.isBefore(maxDate);
                      final isAtMinDate = selectedDate.year == minDate.year &&
                                          selectedDate.month == minDate.month &&
                                          selectedDate.day == minDate.day;
                      
                      final dateFormat = DateFormat('EEE (d MMM)'); // e.g., "Mon (7 Dec)"
                      final backgroundColor = isCurrentDate 
                          ? Colors.green.withOpacity(0.1)
                          : isPastDate 
                              ? Colors.red.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1);
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: backgroundColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCurrentDate 
                                    ? Colors.green 
                                    : isPastDate 
                                        ? Colors.red 
                                        : Colors.grey,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left, size: 24),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: isAtMinDate
                                        ? null
                                        : () {
                                            final newDate = selectedDate.subtract(const Duration(days: 1));
                                            if (newDate.isAfter(minDate) || 
                                                (newDate.year == minDate.year &&
                                                 newDate.month == minDate.month &&
                                                 newDate.day == minDate.day)) {
                                              setState(() {
                                                _selectedDate = newDate;
                                              });
                                            }
                                          },
                                  ),
                                  Flexible(
                                    child: Text(
                                      dateFormat.format(selectedDate),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right, size: 24),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: isCurrentDate
                                        ? null
                                        : () {
                                            final newDate = selectedDate.add(const Duration(days: 1));
                                            if (newDate.isBefore(maxDate) || 
                                                (newDate.year == maxDate.year &&
                                                 newDate.month == maxDate.month &&
                                                 newDate.day == maxDate.day)) {
                                              setState(() {
                                                _selectedDate = newDate;
                                              });
                                            }
                                          },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Reset to Today button when date is not today
                          if (!isCurrentDate) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedDate = DateTime.now();
                                  });
                                },
                                child: const Text(
                                  'Reset to Today',
                                  style: TextStyle(
                                    fontSize: 14,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Time (formatted same as Start Time in timesheet)
                  _buildLabeledInput(
                    label: 'TIME',
                    child: Builder(
                      builder: (context) {
                        final timeOptions = _generateTimeOptions();
                        return DropdownButtonFormField<String>(
                          value: _time.isEmpty ? null : _time,
                          decoration: const InputDecoration(
                            labelText: 'Time',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          ),
                          selectedItemBuilder: (BuildContext context) {
                            return timeOptions.map((time) {
                              return Text(
                                _convertTo12Hour(time),
                                textAlign: TextAlign.center,
                              );
                            }).toList();
                          },
                          items: timeOptions.map((time) {
                            return DropdownMenuItem(
                              value: time,
                              child: Text(
                                _convertTo12Hour(time),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _time = value ?? '';
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Vehicle
                  _buildLabeledInput(
                    label: 'VEHICLE',
                    child: DropdownButtonFormField<String>(
                      value: _selectedLargePlantId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: _largePlant.map((plant) {
                        final desc = plant['plant_description']?.toString() ?? '';
                        return DropdownMenuItem(
                          value: plant['id']?.toString(),
                          child: Text(desc),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedLargePlantId = value;
                        });
                        if (value != null && value.isNotEmpty) {
                          AssetCheckService.updateUserStockLocation(value);
                        }
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a vehicle';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionSection() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF005AB0), width: 2),
                ),
              ),
              child: const Center(
                child: Text(
                  'Collection',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Project Filter
                  _buildLabeledInput(
                    label: 'PROJ_FILTER',
                    child: TextFormField(
                      key: ValueKey('from_project_filter_$_fromProjectFilterResetCounter'),
                      initialValue: _fromProjectFilter,
                      decoration: InputDecoration(
                        labelText: 'Filter Projects (multiple search strings)',
                        hintText: 'Enter search terms separated by spaces',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _fromProjectFilter.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _fromProjectFilter = '';
                                    _fromProjectFilterResetCounter++;
                                  });
                                },
                                tooltip: 'Clear filter',
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _fromProjectFilter = value;
                          
                          // Check if the currently selected project is still in the filtered list
                          if (_selectedFromProjectName != null && _selectedFromProjectName!.isNotEmpty) {
                            final filterTerms = value.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                            final selectedProjectName = _selectedFromProjectName!.toLowerCase();
                            
                            final isStillInFilter = filterTerms.isEmpty || 
                                filterTerms.every((term) => selectedProjectName.contains(term));
                            
                            final filteredProjects = _projects.where((project) {
                              if (value.isEmpty) return true;
                              final name = project['project_name']?.toString().toLowerCase() ?? '';
                              return filterTerms.every((term) => name.contains(term));
                            }).toList();
                            
                            final projectExists = filteredProjects.any(
                              (p) => p['project_name']?.toString() == _selectedFromProjectName
                            );
                            
                            if (!isStillInFilter || !projectExists) {
                              _selectedFromProjectId = null;
                              _selectedFromProjectName = null;
                              _fromProjectSelected = false;
                            }
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Project Dropdown
                  _buildLabeledInput(
                    label: 'PROJECT',
                    child: DropdownButtonFormField<String>(
                      value: _selectedFromProjectId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Select Project',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      selectedItemBuilder: (BuildContext context) {
                        final filteredProjects = _projects.where((project) {
                          if (_fromProjectFilter.isEmpty) return true;
                          final name = project['project_name']?.toString().toLowerCase() ?? '';
                          final filterTerms = _fromProjectFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                          return filterTerms.every((term) => name.contains(term));
                        }).toList();
                        
                        final seenNames = <String>{};
                        final uniqueProjects = <Map<String, dynamic>>[];
                        for (final project in filteredProjects) {
                          final name = project['project_name']?.toString() ?? '';
                          if (name.isNotEmpty && !seenNames.contains(name)) {
                            seenNames.add(name);
                            uniqueProjects.add(project);
                          }
                        }
                        
                        return uniqueProjects.map((project) {
                          final name = project['project_name']?.toString() ?? '';
                          final commaIndex = name.indexOf(',');
                          final projectNumber = commaIndex > 0 ? name.substring(0, commaIndex).trim() : name.trim();
                          
                          return Text(
                            projectNumber,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          );
                        }).toList();
                      },
                      items: _projects.where((project) {
                        if (_fromProjectFilter.isEmpty) return true;
                        final name = project['project_name']?.toString().toLowerCase() ?? '';
                        final filterTerms = _fromProjectFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                        return filterTerms.every((term) => name.contains(term));
                      }).map((project) {
                        final name = project['project_name']?.toString() ?? '';
                        return DropdownMenuItem(
                          value: project['id']?.toString(),
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          if (value != null) {
                            final project = _projectMapById[value];
                            _selectedFromProjectId = value;
                            _selectedFromProjectName = project?['project_name']?.toString();
                            _fromProjectSelected = true;
                          } else {
                            _selectedFromProjectId = null;
                            _selectedFromProjectName = null;
                            _fromProjectSelected = false;
                          }
                        });
                      },
                    ),
                  ),
                  // Project Details
                  if (_fromProjectSelected && _selectedFromProjectName != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _buildProjectDetailsContent(_selectedFromProjectId),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialsSection() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF005AB0), width: 2),
                ),
              ),
              child: const Center(
                child: Text(
                  'Materials',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Material
                  _buildLabeledInput(
                    label: 'MATERIAL',
                    child: DropdownButtonFormField<String>(
                      value: _selectedMaterialId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Select Material'),
                        ),
                        ..._materials.map((material) {
                          final name = material['material_name']?.toString() ?? '';
                          final ewc = material['ewc_code']?.toString() ?? '';
                          return DropdownMenuItem(
                            value: material['id']?.toString(),
                            child: Text(ewc.isNotEmpty ? '$name ($ewc)' : name),
                          );
                        }).toList(),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedMaterialId = value;
                          // Auto-fill EWC code if available
                          if (value != null) {
                            final material = _materials.firstWhere(
                              (m) => m['id']?.toString() == value,
                              orElse: () => {},
                            );
                            if (material.isNotEmpty) {
                              _ewcCodeController.text = material['ewc_code']?.toString() ?? '';
                            }
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  // EWC Code
                  _buildLabeledInput(
                    label: 'EWC CODE',
                    child: TextFormField(
                      controller: _ewcCodeController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Enter EWC code if not selected above',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Quantity
                  _buildLabeledInput(
                    label: 'QUANTITY',
                    child: TextFormField(
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Enter quantity',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Waste Description
                  _buildLabeledInput(
                    label: 'WASTE DESCRIPTION',
                    child: TextFormField(
                      controller: _wasteDescriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Enter waste description',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliverySection() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF005AB0), width: 2),
                ),
              ),
              child: const Center(
                child: Text(
                  'Delivery',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Project Filter
                  _buildLabeledInput(
                    label: 'PROJ_FILTER',
                    child: TextFormField(
                      key: ValueKey('to_project_filter_$_toProjectFilterResetCounter'),
                      initialValue: _toProjectFilter,
                      decoration: InputDecoration(
                        labelText: 'Filter Projects (multiple search strings)',
                        hintText: 'Enter search terms separated by spaces',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _toProjectFilter.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _toProjectFilter = '';
                                    _toProjectFilterResetCounter++;
                                  });
                                },
                                tooltip: 'Clear filter',
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _toProjectFilter = value;
                          
                          // Check if the currently selected project is still in the filtered list
                          if (_selectedToProjectName != null && _selectedToProjectName!.isNotEmpty) {
                            final filterTerms = value.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                            final selectedProjectName = _selectedToProjectName!.toLowerCase();
                            
                            final isStillInFilter = filterTerms.isEmpty || 
                                filterTerms.every((term) => selectedProjectName.contains(term));
                            
                            final filteredProjects = _projects.where((project) {
                              if (value.isEmpty) return true;
                              final name = project['project_name']?.toString().toLowerCase() ?? '';
                              return filterTerms.every((term) => name.contains(term));
                            }).toList();
                            
                            final projectExists = filteredProjects.any(
                              (p) => p['project_name']?.toString() == _selectedToProjectName
                            );
                            
                            if (!isStillInFilter || !projectExists) {
                              _selectedToProjectId = null;
                              _selectedToProjectName = null;
                              _toProjectSelected = false;
                            }
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Project Dropdown
                  _buildLabeledInput(
                    label: 'PROJECT',
                    child: Builder(
                      builder: (context) {
                        // Build filtered and deduplicated project list
                        final filteredProjects = _projects.where((project) {
                          if (_toProjectFilter.isEmpty) return true;
                          final name = project['project_name']?.toString().toLowerCase() ?? '';
                          final filterTerms = _toProjectFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                          return filterTerms.every((term) => name.contains(term));
                        }).toList();
                        
                        final seenNames = <String>{};
                        final uniqueProjects = <Map<String, dynamic>>[];
                        for (final project in filteredProjects) {
                          final name = project['project_name']?.toString() ?? '';
                          if (name.isNotEmpty && !seenNames.contains(name)) {
                            seenNames.add(name);
                            uniqueProjects.add(project);
                          }
                        }
                        
                        return DropdownButtonFormField<String>(
                          value: _selectedToProjectId, // This will be null initially, so it shows "None"
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Select Project',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          selectedItemBuilder: (BuildContext context) {
                            // Must match items list exactly, including "None" option
                            return [
                              const Text('None'),
                              ...uniqueProjects.map((project) {
                                final name = project['project_name']?.toString() ?? '';
                                final commaIndex = name.indexOf(',');
                                final projectNumber = commaIndex > 0 ? name.substring(0, commaIndex).trim() : name.trim();
                                
                                return Text(
                                  projectNumber,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                );
                              }),
                            ];
                          },
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('None'),
                            ),
                            ...uniqueProjects.map((project) {
                              final name = project['project_name']?.toString() ?? '';
                              return DropdownMenuItem(
                                value: project['id']?.toString(),
                                child: Text(name),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) {
                            setState(() {
                              if (value != null) {
                                final project = _projectMapById[value];
                                _selectedToProjectId = value;
                                _selectedToProjectName = project?['project_name']?.toString();
                                _toProjectSelected = true;
                                // Clear facility when project is selected
                                _selectedFacilityId = null;
                              } else {
                                _selectedToProjectId = null;
                                _selectedToProjectName = null;
                                _toProjectSelected = false;
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Waste Facility
                  _buildLabeledInput(
                    label: 'WASTE FACILITY',
                    child: DropdownButtonFormField<String>(
                      value: _selectedFacilityId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Select Facility',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Select Facility'),
                        ),
                        ..._wasteFacilities.where((facility) {
                          final id = facility['id']?.toString();
                          final name = facility['facility_name']?.toString();
                          return id != null && id.isNotEmpty && name != null && name.isNotEmpty;
                        }).map((facility) {
                          final id = facility['id']?.toString() ?? '';
                          final name = facility['facility_name']?.toString() ?? 'Unknown';
                          final town = facility['facility_town']?.toString() ?? '';
                          final displayText = town.isNotEmpty ? '$name, $town' : name;
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(displayText),
                          );
                        }).toList(),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedFacilityId = value;
                          // Clear project when facility is selected
                          if (value != null) {
                            _selectedToProjectId = null;
                            _selectedToProjectName = null;
                            _toProjectSelected = false;
                          }
                        });
                      },
                    ),
                  ),
                  // Show either Project Details OR Facility Summary (but not both)
                  if (_toProjectSelected && _selectedToProjectId != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _buildProjectDetailsContent(_selectedToProjectId),
                    ),
                  ] else if (_selectedFacilityId != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _buildFacilitySummaryContent(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Receiver Signature
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'RECEIVER SIGNATURE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _showSignatureDialog,
                            icon: Icon(_hasSignature ? Icons.check_circle : Icons.edit),
                            label: Text(_hasSignature ? 'Signature Captured' : 'Capture Signature'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _hasSignature ? Colors.green : Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Docket Photo
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'DOCKET PHOTO',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_docketPhoto != null)
                            Image.file(
                              File(_docketPhoto!.path),
                              height: 200,
                              fit: BoxFit.cover,
                            ),
                          if (_docketPhoto != null) const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _pickDocketPhoto,
                            icon: const Icon(Icons.camera_alt),
                            label: Text(_docketPhoto == null ? 'Take Photo' : 'Change Photo'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectDetailsContent(String? projectId) {
    if (projectId == null) return const SizedBox.shrink();
    
    final project = _projectMapById[projectId];
    if (project == null) return const SizedBox.shrink();
    
    final projectName = project['project_name']?.toString() ?? 'Not specified';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Project Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0081FB),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Project Name:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              projectName,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFacilitySummaryContent() {
    if (_selectedFacilityId == null) return const SizedBox.shrink();
    
    final facility = _wasteFacilities.firstWhere(
      (f) => f['id']?.toString() == _selectedFacilityId,
      orElse: () => {},
    );
    
    if (facility.isEmpty) return const SizedBox.shrink();
    
    final name = facility['facility_name']?.toString() ?? 'Not specified';
    final address = facility['facility_address']?.toString() ?? '';
    final town = facility['facility_town']?.toString() ?? '';
    final county = facility['facility_county']?.toString() ?? '';
    final eircode = facility['facility_eircode']?.toString() ?? '';
    final phone = facility['facility_phone']?.toString() ?? '';
    final epaLicence = facility['epa_licence_no']?.toString() ?? '';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Facility Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0081FB),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (name.isNotEmpty) ...[
          _buildDetailRow('Facility Name:', name),
        ],
        if (address.isNotEmpty) ...[
          _buildDetailRow('Address:', address),
        ],
        if (town.isNotEmpty || county.isNotEmpty) ...[
          _buildDetailRow('Location:', [town, county].where((s) => s.isNotEmpty).join(', ')),
        ],
        if (eircode.isNotEmpty) ...[
          _buildDetailRow('Eircode:', eircode),
        ],
        if (phone.isNotEmpty) ...[
          _buildDetailRow('Phone:', phone),
        ],
        if (epaLicence.isNotEmpty) ...[
          _buildDetailRow('EPA Licence:', epaLicence),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildLabeledInput({
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

