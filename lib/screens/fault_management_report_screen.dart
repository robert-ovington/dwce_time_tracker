/// Small Plant Fault Management Report Screen
/// 
/// Manages faults submitted to public.small_plant_faults
/// Allows users to manage repairs and update fault status

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import '../config/supabase_config.dart';
import '../modules/auth/auth_service.dart';
import '../modules/errors/error_log_service.dart';
import 'package:intl/intl.dart';

class SmallPlantFaultManagementReportScreen extends StatefulWidget {
  const SmallPlantFaultManagementReportScreen({super.key});

  @override
  State<SmallPlantFaultManagementReportScreen> createState() => _SmallPlantFaultManagementReportScreenState();
}

class _SmallPlantFaultManagementReportScreenState extends State<SmallPlantFaultManagementReportScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _faults = [];
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, pending, repaired, replaced, disposed, no_action
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadFaults();
  }

  Future<void> _loadFaults() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Load faults - query without nested relationships
      final response = await SupabaseService.client
          .from('small_plant_faults')
          .select('*')
          .order('created_at', ascending: false);

      // Get all unique check IDs to fetch check data
      final checkIds = response
          .map((fault) => fault['small_plant_check_id'] as String?)
          .where((id) => id != null)
          .toSet()
          .toList();

      // Fetch check records
      final Map<String, Map<String, dynamic>> checkDataMap = {};
      if (checkIds.isNotEmpty) {
        try {
          final checkResponse = await SupabaseService.client
              .from('small_plant_check')
              .select('id, small_plant_no, stock_location, date, user_id');
          
          for (final check in checkResponse) {
            final checkId = check['id'] as String?;
            if (checkId != null) {
              checkDataMap[checkId] = check;
            }
          }
        } catch (e) {
          print('Error loading check data: $e');
        }
      }

      // Get all unique plant numbers to fetch plant details
      final plantNumbers = checkDataMap.values
          .map((check) => check['small_plant_no'] as String?)
          .where((no) => no != null)
          .toSet()
          .toList();

      // Fetch plant details
      final Map<String, Map<String, dynamic>> plantDetails = {};
      if (plantNumbers.isNotEmpty) {
        try {
          final plantResponse = await SupabaseService.client
              .from('small_plant')
              .select('small_plant_no, small_plant_description, type, make_model')
              .eq('is_active', true);
          
          for (final plant in plantResponse) {
            final plantNo = plant['small_plant_no'] as String?;
            if (plantNo != null && plantNumbers.contains(plantNo)) {
              plantDetails[plantNo] = plant;
            }
          }
        } catch (e) {
          print('Error loading plant details: $e');
        }
      }

      // Get all unique user IDs to fetch user names
      final userIds = <String>{};
      for (final check in checkDataMap.values) {
        final userId = check['user_id'] as String?;
        if (userId != null) userIds.add(userId);
      }
      for (final fault in response) {
        final supervisorId = fault['supervisor_id'] as String?;
        if (supervisorId != null) userIds.add(supervisorId);
      }

      // Fetch user names
      final Map<String, String> userNames = {};
      if (userIds.isNotEmpty) {
        try {
          final userList = userIds.toList();
          for (final userId in userList) {
            try {
              final userResponse = await SupabaseService.client
                  .from('users_data')
                  .select('forename, surname')
                  .eq('user_id', userId)
                  .maybeSingle();
              
              if (userResponse != null) {
                final forename = userResponse['forename'] as String? ?? '';
                final surname = userResponse['surname'] as String? ?? '';
                userNames[userId] = '$forename $surname'.trim();
              }
            } catch (e) {
              // Continue without this user's name
            }
          }
        } catch (e) {
          print('Error loading user names: $e');
        }
      }

      // Enrich faults with related data
      final List<Map<String, dynamic>> faults = [];
      for (final fault in response) {
        final checkId = fault['small_plant_check_id'] as String?;
        final checkData = checkId != null ? checkDataMap[checkId] : null;
        final plantNo = checkData?['small_plant_no'] as String?;
        final plantData = plantNo != null ? plantDetails[plantNo] : null;
        final userId = checkData?['user_id'] as String?;
        final supervisorId = fault['supervisor_id'] as String?;

        faults.add({
          ...fault,
          'plant_no': plantNo,
          'stock_location': checkData?['stock_location'],
          'check_date': checkData?['date'],
          'user_name': userId != null ? (userNames[userId] ?? 'Unknown') : 'Unknown',
          'supervisor_name': supervisorId != null ? userNames[supervisorId] : null,
          'description': plantData?['small_plant_description'] as String?,
          'type': plantData?['type'] as String?,
          'make_model': plantData?['make_model'] as String?,
        });
      }

      setState(() {
        _faults = faults;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Fault Management Report - Load Data',
        type: 'Database',
        description: 'Failed to load faults: $e',
        stackTrace: stackTrace,
      );
      
      setState(() {
        _errorMessage = 'Failed to load faults: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredFaults {
    var filtered = _faults;
    
    // Filter by status
    if (_filterStatus != 'all') {
      filtered = filtered.where((fault) {
        final actionType = (fault['action_type'] as String? ?? '').toLowerCase();
        if (_filterStatus == 'pending') {
          return actionType.isEmpty || actionType == 'pending_review';
        }
        return actionType == _filterStatus;
      }).toList();
    }
    
    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((fault) {
        final plantNo = (fault['plant_no'] as String? ?? '').toLowerCase();
        final comment = (fault['comment'] as String? ?? '').toLowerCase();
        final description = (fault['description'] as String? ?? '').toLowerCase();
        final location = (fault['stock_location'] as String? ?? '').toLowerCase();
        
        return plantNo.contains(query) ||
            comment.contains(query) ||
            description.contains(query) ||
            location.contains(query);
      }).toList();
    }
    
    return filtered;
  }

  Future<void> _updateFaultStatus(
    String faultId,
    String actionType,
    DateTime? actionDate,
    String? actionNotes,
  ) async {
    try {
      final currentUserId = AuthService.getCurrentUser()?.id;
      if (currentUserId == null) {
        throw Exception('User not logged in');
      }

      final updateData = <String, dynamic>{
        'action_type': actionType,
        'supervisor_id': currentUserId,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (actionDate != null) {
        updateData['action_date'] = actionDate.toIso8601String();
      }

      if (actionNotes != null && actionNotes.isNotEmpty) {
        updateData['action_notes'] = actionNotes;
      }

      await SupabaseService.client
          .from('small_plant_faults')
          .update(updateData)
          .eq('id', faultId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fault status updated successfully')),
        );
        _loadFaults();
      }
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Fault Management Report - Update Status',
        type: 'Database',
        description: 'Failed to update fault status: $e',
        stackTrace: stackTrace,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update fault: $e')),
        );
      }
    }
  }

  void _showUpdateDialog(Map<String, dynamic> fault) {
    final actionTypeController = TextEditingController(
      text: fault['action_type'] as String? ?? '',
    );
    final actionNotesController = TextEditingController(
      text: fault['action_notes'] as String? ?? '',
    );
    DateTime? selectedDate;
    
    final actionDateStr = fault['action_date'] as String?;
    if (actionDateStr != null) {
      try {
        selectedDate = DateTime.parse(actionDateStr);
      } catch (e) {
        // Invalid date
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Update Fault Status'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plant: ${fault['plant_no'] ?? 'Unknown'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Action Type',
                    border: OutlineInputBorder(),
                  ),
                  value: actionTypeController.text.isEmpty 
                      ? null 
                      : actionTypeController.text,
                  items: const [
                    DropdownMenuItem(value: 'pending_review', child: Text('Pending Review')),
                    DropdownMenuItem(value: 'repaired', child: Text('Repaired')),
                    DropdownMenuItem(value: 'replaced', child: Text('Replaced')),
                    DropdownMenuItem(value: 'disposed', child: Text('Disposed')),
                    DropdownMenuItem(value: 'no_action_required', child: Text('No Action Required')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      actionTypeController.text = value;
                      setDialogState(() {});
                    }
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: Text(
                    selectedDate == null
                        ? 'Select Action Date'
                        : 'Action Date: ${DateFormat('dd/MM/yyyy').format(selectedDate!)}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setDialogState(() {
                        selectedDate = date;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: actionNotesController,
                  decoration: const InputDecoration(
                    labelText: 'Action Notes',
                    border: OutlineInputBorder(),
                    hintText: 'Enter notes about the action taken...',
                  ),
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final actionType = actionTypeController.text.trim();
                if (actionType.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select an action type')),
                  );
                  return;
                }
                
                _updateFaultStatus(
                  fault['id'] as String,
                  actionType,
                  selectedDate,
                  actionNotesController.text.trim().isEmpty
                      ? null
                      : actionNotesController.text.trim(),
                );
                Navigator.pop(context);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Small Plant Fault Management',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'fault_management_report_screen.dart')],
      ),
      body: Column(
        children: [
          // Search and filter bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by plant number, comment, description...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'All'),
                      const SizedBox(width: 8),
                      _buildFilterChip('pending', 'Pending'),
                      const SizedBox(width: 8),
                      _buildFilterChip('repaired', 'Repaired'),
                      const SizedBox(width: 8),
                      _buildFilterChip('replaced', 'Replaced'),
                      const SizedBox(width: 8),
                      _buildFilterChip('disposed', 'Disposed'),
                      const SizedBox(width: 8),
                      _buildFilterChip('no_action_required', 'No Action'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Results count and refresh
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_filteredFaults.length} fault${_filteredFaults.length != 1 ? 's' : ''} found',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadFaults,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 64,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadFaults,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredFaults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.construction,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty && _filterStatus == 'all'
                                      ? 'No faults found'
                                      : 'No results found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            itemCount: _filteredFaults.length,
                            itemBuilder: (context, index) {
                              final fault = _filteredFaults[index];
                              return _buildFaultCard(fault);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = value;
        });
      },
      selectedColor: Colors.orange.withOpacity(0.3),
      checkmarkColor: Colors.orange,
    );
  }

  Widget _buildFaultCard(Map<String, dynamic> fault) {
    final plantNo = fault['plant_no'] as String? ?? 'Unknown';
    final comment = fault['comment'] as String? ?? '';
    final photoUrl = fault['photo_url'] as String?;
    final actionType = fault['action_type'] as String?;
    final actionDate = fault['action_date'] as String?;
    final actionNotes = fault['action_notes'] as String?;
    final stockLocation = fault['stock_location'] as String?;
    final userName = fault['user_name'] as String?;
    final supervisorName = fault['supervisor_name'] as String?;
    final description = fault['description'] as String?;
    
    DateTime? actionDateTime;
    if (actionDate != null) {
      try {
        actionDateTime = DateTime.parse(actionDate);
      } catch (e) {
        // Invalid date
      }
    }

    final statusColor = _getStatusColor(actionType);
    final statusLabel = _getStatusLabel(actionType);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.construction,
            color: statusColor,
          ),
        ),
        title: Text(
          plantNo,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              comment.length > 50 ? '${comment.substring(0, 50)}...' : comment,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => _showUpdateDialog(fault),
          tooltip: 'Update Status',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (description != null) ...[
                  _buildInfoRow('Description', description),
                  const SizedBox(height: 8),
                ],
                if (stockLocation != null) ...[
                  _buildInfoRow('Location', stockLocation),
                  const SizedBox(height: 8),
                ],
                _buildInfoRow('Fault Comment', comment),
                const SizedBox(height: 8),
                _buildInfoRow('Reported By', userName ?? 'Unknown'),
                if (actionType != null) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow('Status', statusLabel),
                ],
                if (actionDateTime != null) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow('Action Date', DateFormat('dd/MM/yyyy').format(actionDateTime)),
                ],
                if (supervisorName != null) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow('Supervisor', supervisorName),
                ],
                if (actionNotes != null && actionNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow('Action Notes', actionNotes),
                ],
                if (photoUrl != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Photo:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppBar(
                                title: const Text(
                                  'Fault Photo',
                                  style: TextStyle(color: Colors.black),
                                ),
                                centerTitle: true,
                                backgroundColor: const Color(0xFF0081FB),
                                foregroundColor: Colors.black,
                                actions: const [ScreenInfoIcon(screenName: 'fault_management_report_screen.dart')],
                              ),
                              Flexible(
                                child: Image.network(
                                  photoUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Padding(
                                      padding: EdgeInsets.all(24.0),
                                      child: Text('Failed to load image'),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        photoUrl,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 200,
                            color: Colors.grey[300],
                            child: const Center(
                              child: Icon(Icons.broken_image),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String? actionType) {
    switch (actionType?.toLowerCase()) {
      case 'repaired':
        return Colors.green;
      case 'replaced':
        return Colors.blue;
      case 'disposed':
        return Colors.red;
      case 'no_action_required':
        return Colors.grey;
      case 'pending_review':
      default:
        return Colors.orange;
    }
  }

  String _getStatusLabel(String? actionType) {
    switch (actionType?.toLowerCase()) {
      case 'repaired':
        return 'Repaired';
      case 'replaced':
        return 'Replaced';
      case 'disposed':
        return 'Disposed';
      case 'no_action_required':
        return 'No Action Required';
      case 'pending_review':
        return 'Pending Review';
      default:
        return 'Pending';
    }
  }
}

