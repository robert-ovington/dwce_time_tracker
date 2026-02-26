/// Asset Check Screen
/// 
/// Screen for scanning NFC-tagged small tools into Supabase.
/// Supports fault reporting with optional photo upload.
/// 
/// Flow:
/// 1. User selects stock location (van/vehicle)
/// 2. Taps "Start Scan" to enter scanning mode
/// 3. Holds device near NFC tags (format: SP1234 - SP followed by 4 digits)
/// 4. Each scan validates against small_plant table
/// 5. User can report faults for scanned items
/// 6. On submit, creates records in small_plant_check and small_plant_faults

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../modules/asset_check/asset_check_service.dart';
import '../modules/asset_check/asset_check_models.dart';
import '../modules/asset_check/nfc_helper.dart';
import '../modules/asset_check/photo_upload_helper.dart';
import '../modules/asset_check/scan_feedback_helper.dart';
import '../modules/auth/auth_service.dart';
import '../modules/errors/error_log_service.dart';

class AssetCheckScreen extends StatefulWidget {
  const AssetCheckScreen({super.key});

  @override
  State<AssetCheckScreen> createState() => _AssetCheckScreenState();
}

class _AssetCheckScreenState extends State<AssetCheckScreen> {
  // State
  bool _isLoading = false;
  bool _isScanning = false;
  String? _errorMessage;
  
  // Stock location
  List<String> _stockLocations = [];
  String? _selectedStockLocation;
  String? _userDefaultStockLocation;
  String _stockLocationFilter = '';
  
  // Scanned items
  final List<ScannedItem> _scannedItems = [];
  final Set<String> _scannedPlantNos = {}; // For duplicate detection
  
  // Fault data storage (temporary until submit)
  final Map<String, Map<String, dynamic>> _faultData = {}; // Key: small_plant_no
  
  // Scan input (for debug/testing)
  final TextEditingController _scanInputController = TextEditingController();
  final FocusNode _scanInputFocus = FocusNode();
  bool _showDebugScanner = false; // Set to true for testing without NFC
  
  // NFC scanning state
  bool _isNfcScanning = false;
  bool _nfcAvailable = false;
  
  // Last scan feedback timer
  Timer? _readyForNextScanTimer;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
    ScanFeedbackHelper.initialize();
    _checkNfcAvailability();
  }

  Future<void> _checkNfcAvailability() async {
    final available = await NfcHelper.isAvailable();
    setState(() {
      _nfcAvailable = available;
    });
    
    if (!available) {
      // NFC not available - show message or enable debug scanner
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NFC is not available on this device. Use Manual Entry or enable debug scanner.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _scanInputController.dispose();
    _scanInputFocus.dispose();
    _readyForNextScanTimer?.cancel();
    // Stop NFC scanning if active
    if (_isNfcScanning) {
      NfcHelper.stopScanning();
    }
    ScanFeedbackHelper.dispose();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load stock locations and user default in parallel
      final results = await Future.wait([
        AssetCheckService.getStockLocations(),
        AssetCheckService.getUserStockLocation(),
      ]);

      final stockLocations = results[0] as List<String>;
      final userDefault = results[1] as String?;

      setState(() {
        _stockLocations = stockLocations;
        _userDefaultStockLocation = userDefault;
        _selectedStockLocation = userDefault ?? (stockLocations.isNotEmpty ? stockLocations.first : null);
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Asset Check Screen - Initialize',
        type: 'Database',
        description: 'Failed to initialize screen: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _errorMessage = 'Failed to load data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAsMyStockLocation() async {
    if (_selectedStockLocation == null || _selectedStockLocation!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a stock location first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await AssetCheckService.updateUserStockLocation(_selectedStockLocation!);
      
      setState(() {
        _userDefaultStockLocation = _selectedStockLocation;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stock location "${_selectedStockLocation}" saved as your default'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Asset Check Screen - Save Stock Location',
        type: 'Database',
        description: 'Failed to save stock location: $e',
        stackTrace: stackTrace,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving stock location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startScanning() async {
    if (_selectedStockLocation == null || _selectedStockLocation!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a stock location')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _scannedItems.clear();
      _scannedPlantNos.clear();
      _errorMessage = null;
    });

    // Start NFC scanning if available
    if (_nfcAvailable) {
      final started = await NfcHelper.startScanning(
        onTagDiscovered: (tagId) {
          // Process the scanned NFC tag
          _handleScan(tagId);
        },
        onError: (error) {
          if (mounted) {
            // Show detailed error in a dialog for better visibility
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('NFC Error'),
                content: SingleChildScrollView(
                  child: Text(
                    error,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
            // Also show a snackbar for quick notification
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('NFC Error: ${error.split('\n').first}'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
      );

      if (started) {
        setState(() {
          _isNfcScanning = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('NFC scanning started. Hold your device near an NFC tag.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        setState(() {
          _isScanning = false;
        });
      }
    } else {
      // NFC not available - show message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NFC not available. Please use Manual Entry.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      setState(() {
        _isScanning = false;
      });
    }

    // Focus scan input if debug scanner is enabled
    if (_showDebugScanner) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _scanInputFocus.requestFocus();
        }
      });
    }
  }

  void _stopScanning() async {
    // Stop NFC scanning
    if (_isNfcScanning) {
      await NfcHelper.stopScanning();
      setState(() {
        _isNfcScanning = false;
      });
    }
    
    setState(() {
      _isScanning = false;
    });
    _readyForNextScanTimer?.cancel();
  }

  Future<void> _handleScan(String scannedCode) async {
    // Validate format: SP followed by 4 digits (e.g., "SP1234")
    if (!RegExp(r'^SP\d{4}$').hasMatch(scannedCode)) {
      await ScanFeedbackHelper.playError();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid scan format. Expected format: SP1234')),
      );
      return;
    }

    // Check for duplicates
    if (_scannedPlantNos.contains(scannedCode)) {
      await ScanFeedbackHelper.playError();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already scanned')),
      );
      return;
    }

    // Validate against database
    final plantData = await AssetCheckService.validateSmallPlant(scannedCode);
    
    if (plantData == null) {
      await ScanFeedbackHelper.playError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tool not found: $scannedCode')),
      );
      return;
    }

    // Success - add to scanned items
    final scannedItem = ScannedItem(
      smallPlantNo: scannedCode,
      smallPlantDescription: plantData['small_plant_description'] as String?,
      type: plantData['type'] as String?,
      makeModel: plantData['make_model'] as String?,
      serialNumber: plantData['serial_number'] as String?,
      scannedAt: DateTime.now(),
    );

    setState(() {
      _scannedItems.insert(0, scannedItem); // Most recent first
      _scannedPlantNos.add(scannedCode);
    });

    // Success feedback
    await ScanFeedbackHelper.playSuccessSingle();

    // Clear scan input for next scan
    _scanInputController.clear();

    // Play double beep after 2 seconds to indicate ready for next scan
    _readyForNextScanTimer?.cancel();
    _readyForNextScanTimer = Timer(const Duration(seconds: 2), () {
      ScanFeedbackHelper.playSuccessDouble();
    });
  }

  Future<void> _handleDebugScan() async {
    final code = _scanInputController.text.trim();
    if (code.isEmpty) return;
    
    await _handleScan(code);
  }

  void _deleteScannedItem(ScannedItem item) {
    setState(() {
      _scannedItems.remove(item);
      _scannedPlantNos.remove(item.smallPlantNo);
      // Also remove fault data if it exists
      _faultData.remove(item.smallPlantNo);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.smallPlantNo} removed from list'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showManualEntryDialog() async {
    final controller = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual Entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the 4-digit number (SP prefix will be added automatically)',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Enter 4 digits',
                hintText: '1234',
                border: OutlineInputBorder(),
                prefixText: 'SP',
                prefixStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final digits = controller.text.trim();
              if (digits.length == 4 && RegExp(r'^\d{4}$').hasMatch(digits)) {
                Navigator.pop(context, digits);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter exactly 4 digits'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.length == 4) {
      // Prepend "SP" to make the full code
      final fullCode = 'SP$result';
      await _handleScan(fullCode);
    }
  }

  Future<void> _reportFault(ScannedItem item) async {
    // Check if fault already exists
    final existingFault = _faultData[item.smallPlantNo];
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _FaultReportDialog(
        item: item,
        initialComment: existingFault?['comment'] as String?,
        initialPhotoUrl: existingFault?['photoUrl'] as String?,
      ),
    );

    if (result != null && result['comment'] != null) {
      // Store fault data temporarily
      _faultData[item.smallPlantNo] = {
        'comment': result['comment'] as String,
        'photoUrl': result['photoUrl'] as String?,
      };

      // Update item to mark as having fault
      final index = _scannedItems.indexWhere((i) => i.smallPlantNo == item.smallPlantNo);
      if (index != -1) {
        setState(() {
          _scannedItems[index] = item.copyWith(hasFault: true);
        });
      }
    }
  }

  Future<void> _submitScanSession() async {
    if (_scannedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items scanned')),
      );
      return;
    }

    if (_selectedStockLocation == null || _selectedStockLocation!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a stock location')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final today = DateTime.now();
      final plantNos = _scannedItems.map((item) => item.smallPlantNo).toList();

      // Create small_plant_check records
      // Approach: Create records immediately so we have IDs for fault linking
      final checkRecords = await AssetCheckService.createSmallPlantChecksBatch(
        date: today,
        stockLocation: _selectedStockLocation!,
        smallPlantNos: plantNos,
      );

      // Map plant numbers to check IDs
      final plantNoToCheckId = <String, String>{};
      for (final record in checkRecords) {
        final plantNo = record['small_plant_no'] as String;
        final checkId = record['id'] as String;
        plantNoToCheckId[plantNo] = checkId;
      }

      // Create fault records for items with faults
      final faultItems = _scannedItems.where((item) => item.hasFault).toList();
      for (final item in faultItems) {
        final checkId = plantNoToCheckId[item.smallPlantNo];
        final faultData = _faultData[item.smallPlantNo];
        
        if (checkId != null && faultData != null) {
          try {
            await AssetCheckService.createSmallPlantFault(
              smallPlantCheckId: checkId,
              comment: faultData['comment'] as String,
              photoUrl: faultData['photoUrl'] as String?,
            );
          } catch (e, stackTrace) {
            await ErrorLogService.logError(
              location: 'Asset Check Screen - Create Fault',
              type: 'Database',
              description: 'Failed to create fault for ${item.smallPlantNo}: $e',
              stackTrace: stackTrace,
            );
            // Continue with other faults even if one fails
          }
        }
      }

      // Check if stock location changed
      bool shouldUpdateLocation = false;
      if (_selectedStockLocation != _userDefaultStockLocation) {
        final update = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Update Default Location?'),
            content: Text(
              'Update your default stock location to "${_selectedStockLocation}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );

        if (update == true) {
          await AssetCheckService.updateUserStockLocation(_selectedStockLocation!);
          shouldUpdateLocation = true;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan session submitted successfully')),
        );
        
        // Close screen
        Navigator.pop(context);
      }
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Asset Check Screen - Submit',
        type: 'Database',
        description: 'Failed to submit scan session: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _errorMessage = 'Failed to submit: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0081FB),
        title: const Text(
          'Asset Check',
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
        actions: const [ScreenInfoIcon(screenName: 'asset_check_screen.dart')],
      ),
      body: _isLoading && !_isScanning
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // NFC Status Indicator
                  if (_isScanning && _nfcAvailable)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.nfc, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'NFC scanning active. Hold device near an NFC tag.',
                              style: TextStyle(
                                color: Colors.blue.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // Stock Location Filter (similar to timesheet_screen)
                  TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Filter Stock Locations',
                      hintText: 'Enter search terms separated by spaces',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _stockLocationFilter.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setState(() {
                                  _stockLocationFilter = '';
                                });
                              },
                              tooltip: 'Clear filter',
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _stockLocationFilter = value;
                        
                        // Check if the currently selected location is still in the filtered list
                        if (_selectedStockLocation != null && _selectedStockLocation!.isNotEmpty) {
                          final filterTerms = value.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                          final selectedLocation = _selectedStockLocation!.toLowerCase();
                          
                          final isStillInFilter = filterTerms.isEmpty || 
                              filterTerms.any((term) => selectedLocation.contains(term));
                          
                          final filteredLocations = _stockLocations.where((location) {
                            if (value.isEmpty) return true;
                            final name = location.toLowerCase();
                            final filterTerms = value.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                            return filterTerms.any((term) => name.contains(term));
                          }).toList();
                          
                          final locationExists = filteredLocations.contains(_selectedStockLocation);
                          
                          if (!isStillInFilter || !locationExists) {
                            _selectedStockLocation = null;
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Stock Location Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedStockLocation,
                    decoration: const InputDecoration(
                      labelText: 'Stock Location',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: _stockLocations
                        .where((location) {
                          if (_stockLocationFilter.isEmpty) return true;
                          final name = location.toLowerCase();
                          final filterTerms = _stockLocationFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                          return filterTerms.any((term) => name.contains(term));
                        })
                        .map((location) {
                      return DropdownMenuItem(
                        value: location,
                        child: Text(location),
                      );
                    }).toList(),
                    onChanged: _isScanning
                        ? null
                        : (value) {
                            setState(() {
                              _selectedStockLocation = value;
                            });
                          },
                  ),
                  const SizedBox(height: 8),
                  
                  // Save as my Stock Location button
                  OutlinedButton.icon(
                    onPressed: (_isScanning || _selectedStockLocation == null || _selectedStockLocation!.isEmpty)
                        ? null
                        : _saveAsMyStockLocation,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save as my Stock Location'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Start/Stop Scan Button
                  if (!_isScanning)
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _startScanning,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Start Scan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _stopScanning,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop Scan'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showManualEntryDialog,
                            icon: const Icon(Icons.edit),
                            label: const Text('Manual Entry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Debug Scanner (for testing without RFID)
                  if (_showDebugScanner && _isScanning) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _scanInputController,
                      focusNode: _scanInputFocus,
                      decoration: const InputDecoration(
                        labelText: 'Enter code (Format: SP1234)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.qr_code),
                        helperText: 'Format: SP followed by 4 digits',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      onSubmitted: (_) => _handleDebugScan(),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _handleDebugScan,
                      child: const Text('Simulate Scan'),
                    ),
                  ],

                  // Error Message
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],

                  // Scanned Items List
                  if (_isScanning || _scannedItems.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Scanned Items (${_scannedItems.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_scannedItems.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'No items scanned yet. Scan an RFID tag to begin.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _scannedItems.length,
                        itemBuilder: (context, index) {
                          final item = _scannedItems[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                item.smallPlantNo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  if (item.type != null && item.type!.isNotEmpty)
                                    Text(
                                      item.type!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                    ),
                                  if (item.makeModel != null && item.makeModel!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      item.makeModel!,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                  if (item.serialNumber != null && item.serialNumber!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'S/N: ${item.serialNumber!}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                  // Fallback to description if new fields are empty
                                  if ((item.type == null || item.type!.isEmpty) &&
                                      (item.makeModel == null || item.makeModel!.isEmpty) &&
                                      item.smallPlantDescription != null &&
                                      item.smallPlantDescription!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      item.smallPlantDescription!,
                                      style: const TextStyle(fontSize: 13),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (item.hasFault)
                                    const Icon(
                                      Icons.warning,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.report_problem),
                                    onPressed: () => _reportFault(item),
                                    tooltip: 'Report Fault',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.red),
                                    onPressed: () => _deleteScannedItem(item),
                                    tooltip: 'Delete',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],

                  // Submit Button
                  if (!_isScanning && _scannedItems.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submitScanSession,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('Submit Scan Session'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0081FB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Fault Report Dialog
class _FaultReportDialog extends StatefulWidget {
  final ScannedItem item;
  final String? initialComment;
  final String? initialPhotoUrl;

  const _FaultReportDialog({
    required this.item,
    this.initialComment,
    this.initialPhotoUrl,
  });

  @override
  State<_FaultReportDialog> createState() => _FaultReportDialogState();
}

class _FaultReportDialogState extends State<_FaultReportDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _commentController;
  XFile? _selectedImage;
  String? _existingPhotoUrl;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(
      text: widget.initialComment ?? '',
    );
    _existingPhotoUrl = widget.initialPhotoUrl;
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
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
      final image = await PhotoUploadHelper.pickImage(source: source);
      if (image != null && mounted) {
        setState(() {
          _selectedImage = image;
        });
      }
    }
  }

  Future<void> _submitFault() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isUploading = true;
    });

    try {
      String? photoUrl;

      // Upload photo if selected (new photo)
      if (_selectedImage != null) {
        final userId = AuthService.getCurrentUser()?.id ?? 'unknown';
        final fileName = PhotoUploadHelper.generateFileName(
          userId,
          widget.item.smallPlantNo,
        );
        photoUrl = await PhotoUploadHelper.uploadImage(
          imageFile: _selectedImage!,
          fileName: fileName,
        );
      } else if (_existingPhotoUrl != null) {
        // Use existing photo URL
        photoUrl = _existingPhotoUrl;
      }

      if (mounted) {
        Navigator.pop(context, {
          'comment': _commentController.text,
          'photoUrl': photoUrl,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report Fault: ${widget.item.smallPlantNo}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _commentController,
                decoration: const InputDecoration(
                  labelText: 'Comment *',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Comment is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (_selectedImage != null || _existingPhotoUrl != null)
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _selectedImage != null
                        ? Image.file(
                            File(_selectedImage!.path),
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.image, size: 48),
                              );
                            },
                          )
                        : Image.network(
                            _existingPhotoUrl!,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.image, size: 48),
                              );
                            },
                          ),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo),
                label: Text(_selectedImage == null ? 'Add Photo' : 'Change Photo'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _submitFault,
          child: _isUploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

