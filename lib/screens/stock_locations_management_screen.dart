/// Stock Locations Management Screen
/// 
/// Allows users to create and manage entries in the stock_locations table

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import '../config/supabase_config.dart';
import '../modules/database/database_service.dart';
import '../modules/errors/error_log_service.dart';

class StockLocationsManagementScreen extends StatefulWidget {
  const StockLocationsManagementScreen({super.key});

  @override
  State<StockLocationsManagementScreen> createState() => _StockLocationsManagementScreenState();
}

class _StockLocationsManagementScreenState extends State<StockLocationsManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  bool _isActive = true;
  
  List<Map<String, dynamic>> _stockLocations = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _editingId;
  
  @override
  void initState() {
    super.initState();
    _loadStockLocations();
  }
  
  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadStockLocations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await DatabaseService.read(
        'stock_locations',
        orderBy: 'description',
        ascending: true,
      );

      setState(() {
        _stockLocations = response;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Stock Locations Management - Load',
        type: 'Database',
        description: 'Failed to load stock locations: $e',
        stackTrace: stackTrace,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading stock locations: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveStockLocation() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final data = {
        'description': _descriptionController.text.trim(),
        'is_active': _isActive,
      };

      if (_editingId != null) {
        // Update existing
        await DatabaseService.update('stock_locations', _editingId!, data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Stock location updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Create new
        await DatabaseService.create('stock_locations', data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Stock location created successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      // Reset form
      _descriptionController.clear();
      _isActive = true;
      _editingId = null;
      
      // Reload list
      await _loadStockLocations();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Stock Locations Management - Save',
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
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _editStockLocation(Map<String, dynamic> location) {
    setState(() {
      _editingId = location['id']?.toString();
      _descriptionController.text = location['description']?.toString() ?? '';
      _isActive = location['is_active'] as bool? ?? true;
    });
    
    // Scroll to form
    Scrollable.ensureVisible(_formKey.currentContext!);
  }

  Future<void> _deleteStockLocation(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Stock Location'),
        content: const Text('Are you sure you want to delete this stock location?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await DatabaseService.delete('stock_locations', id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock location deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      await _loadStockLocations();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Stock Locations Management - Delete',
        type: 'Database',
        description: 'Failed to delete stock location: $e',
        stackTrace: stackTrace,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting stock location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _cancelEdit() {
    setState(() {
      _descriptionController.clear();
      _isActive = true;
      _editingId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Stock Locations Management',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'stock_locations_management_screen.dart')],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Form section
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _editingId != null ? 'Edit Stock Location' : 'Create New Stock Location',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _descriptionController,
                              decoration: const InputDecoration(
                                labelText: 'Description *',
                                border: OutlineInputBorder(),
                                helperText: 'Stock location description',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a description';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              title: const Text('Active'),
                              subtitle: const Text('Stock location is active and available for selection'),
                              value: _isActive,
                              onChanged: (value) {
                                setState(() {
                                  _isActive = value;
                                });
                              },
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _isSaving ? null : _saveStockLocation,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0081FB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                    child: Text(
                                      _isSaving
                                          ? 'Saving...'
                                          : (_editingId != null ? 'Update' : 'Create'),
                                    ),
                                  ),
                                ),
                                if (_editingId != null) ...[
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _isSaving ? null : _cancelEdit,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // List section
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Stock Locations',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _loadStockLocations,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _stockLocations.isEmpty
                              ? const Center(
                                  child: Text('No stock locations found'),
                                )
                              : ListView.builder(
                                  itemCount: _stockLocations.length,
                                  itemBuilder: (context, index) {
                                    final location = _stockLocations[index];
                                    final id = location['id']?.toString() ?? '';
                                    final description = location['description']?.toString() ?? '';
                                    final isActive = location['is_active'] as bool? ?? true;

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        title: Text(
                                          description,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isActive ? Colors.black : Colors.grey,
                                          ),
                                        ),
                                        subtitle: Text(
                                          isActive ? 'Active' : 'Inactive',
                                          style: TextStyle(
                                            color: isActive ? Colors.green : Colors.red,
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit),
                                              onPressed: () => _editStockLocation(location),
                                              tooltip: 'Edit',
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete, color: Colors.red),
                                              onPressed: () => _deleteStockLocation(id),
                                              tooltip: 'Delete',
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
