/// Small Plant Location Report Screen
/// 
/// Displays the last reported location of small plant items
/// based on data from public.small_plant_check

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import '../modules/asset_check/asset_check_service.dart';
import '../config/supabase_config.dart';
import '../modules/errors/error_log_service.dart';

class SmallPlantLocationReportScreen extends StatefulWidget {
  const SmallPlantLocationReportScreen({super.key});

  @override
  State<SmallPlantLocationReportScreen> createState() => _SmallPlantLocationReportScreenState();
}

class _SmallPlantLocationReportScreenState extends State<SmallPlantLocationReportScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _plantLocations = [];
  String _searchQuery = '';
  String _errorMessage = '';
  List<String> _stockLocations = [];
  String? _selectedStockLocationFilter;

  @override
  void initState() {
    super.initState();
    _loadStockLocations();
    _loadPlantLocations();
  }

  Future<void> _loadStockLocations() async {
    try {
      final locations = <String>[];
      
      // First, load from stock_locations table (active only)
      try {
        final stockLocationsResponse = await SupabaseService.client
            .from('stock_locations')
            .select('description')
            .eq('is_active', true)
            .order('description');
        
        for (var item in stockLocationsResponse) {
          final desc = item['description'] as String?;
          if (desc != null && desc.isNotEmpty) {
            locations.add(desc);
          }
        }
      } catch (e) {
        print('⚠️ Error loading from stock_locations table: $e');
      }
      
      // Then, load from large_plant table (active only, exclude where is_stock_location is NULL)
      try {
        final plantResponse = await SupabaseService.client
            .from('large_plant')
            .select('plant_description, is_stock_location')
            .eq('is_active', true)
            .order('plant_description');
        
        for (var item in plantResponse) {
          // Exclude entries where is_stock_location is NULL
          final isStockLocation = item['is_stock_location'];
          if (isStockLocation == null) {
            continue;
          }
          
          final desc = item['plant_description'] as String?;
          if (desc != null && desc.isNotEmpty && !locations.contains(desc)) {
            locations.add(desc);
          }
        }
      } catch (e) {
        print('⚠️ Error loading from large_plant table: $e');
      }
      
      setState(() {
        _stockLocations = locations;
      });
    } catch (e) {
      print('⚠️ Error loading stock locations: $e');
      setState(() {
        _stockLocations = [];
      });
    }
  }

  Future<void> _loadPlantLocations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Query to get last reported location for each small plant
      // First get all check records ordered by date
      final response = await SupabaseService.client
          .from('small_plant_check')
          .select('small_plant_no, stock_location, date, user_id')
          .order('date', ascending: false);

      // Group by small_plant_no and get the most recent entry for each
      final Map<String, Map<String, dynamic>> latestLocations = {};
      
      for (final record in response) {
        final plantNo = record['small_plant_no'] as String?;
        if (plantNo == null) continue;

        // If we haven't seen this plant or this date is more recent
        if (!latestLocations.containsKey(plantNo)) {
          latestLocations[plantNo] = record;
        } else {
          final existingDate = latestLocations[plantNo]!['date'] as String?;
          final currentDate = record['date'] as String?;
          if (currentDate != null && 
              (existingDate == null || currentDate.compareTo(existingDate) > 0)) {
            latestLocations[plantNo] = record;
          }
        }
      }

      // Get all unique plant numbers to fetch plant details
      final plantNumbers = latestLocations.keys.toList();
      
      // Fetch plant details for all plants
      // Since Supabase doesn't support .in() directly, we'll fetch all active plants
      // and match them (more efficient than individual queries)
      final Map<String, Map<String, dynamic>> plantDetails = {};
      if (plantNumbers.isNotEmpty) {
        try {
          // Fetch all active small plants and filter in memory
          final plantResponse = await SupabaseService.client
              .from('small_plant')
              .select('small_plant_no, small_plant_description, type, make_model, serial_number')
              .eq('is_active', true);
          
          for (final plant in plantResponse) {
            final plantNo = plant['small_plant_no'] as String?;
            if (plantNo != null && plantNumbers.contains(plantNo)) {
              plantDetails[plantNo] = plant;
            }
          }
        } catch (e) {
          // If plant lookup fails, continue without plant details
          print('Error loading plant details: $e');
        }
      }

      // Convert to list and get user info
      final List<Map<String, dynamic>> locations = [];
      for (final entry in latestLocations.values) {
        final plantNo = entry['small_plant_no'] as String?;
        final userId = entry['user_id'] as String?;
        String? userName;
        
        if (userId != null) {
          try {
            final userResponse = await SupabaseService.client
                .from('users_data')
                .select('forename, surname')
                .eq('user_id', userId)
                .maybeSingle();
            
            if (userResponse != null) {
              final forename = userResponse['forename'] as String? ?? '';
              final surname = userResponse['surname'] as String? ?? '';
              userName = '$forename $surname'.trim();
            }
          } catch (e) {
            // If user lookup fails, continue without name
          }
        }

        final plantData = plantNo != null ? plantDetails[plantNo] : null;
        locations.add({
          'small_plant_no': plantNo,
          'stock_location': entry['stock_location'],
          'date': entry['date'],
          'user_name': userName ?? 'Unknown',
          'description': plantData?['small_plant_description'] as String?,
          'type': plantData?['type'] as String?,
          'make_model': plantData?['make_model'] as String?,
          'serial_number': plantData?['serial_number'] as String?,
        });
      }

      // Sort by plant number
      locations.sort((a, b) {
        final aNo = (a['small_plant_no'] as String? ?? '').toUpperCase();
        final bNo = (b['small_plant_no'] as String? ?? '').toUpperCase();
        return aNo.compareTo(bNo);
      });

      setState(() {
        _plantLocations = locations;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Plant Location Report - Load Data',
        type: 'Database',
        description: 'Failed to load plant locations: $e',
        stackTrace: stackTrace,
      );
      
      setState(() {
        _errorMessage = 'Failed to load plant locations: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredLocations {
    var filtered = _plantLocations;
    
    // Filter by stock location if selected
    if (_selectedStockLocationFilter != null && _selectedStockLocationFilter!.isNotEmpty) {
      filtered = filtered.where((location) {
        final stockLocation = location['stock_location'] as String? ?? '';
        return stockLocation == _selectedStockLocationFilter;
      }).toList();
    }
    
    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((location) {
        final plantNo = (location['small_plant_no'] as String? ?? '').toLowerCase();
        final description = (location['description'] as String? ?? '').toLowerCase();
        final locationName = (location['stock_location'] as String? ?? '').toLowerCase();
        final type = (location['type'] as String? ?? '').toLowerCase();
        
        return plantNo.contains(query) ||
            description.contains(query) ||
            locationName.contains(query) ||
            type.contains(query);
      }).toList();
    }
    
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Small Plant Location Report',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'plant_location_report_screen.dart')],
      ),
      body: Column(
        children: [
          // Search bar and Stock Location filter
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by plant number, description, location, or type...',
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
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedStockLocationFilter,
                  decoration: const InputDecoration(
                    labelText: 'Stock Location',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All Locations'),
                    ),
                    ..._stockLocations.map((location) {
                      return DropdownMenuItem(
                        value: location,
                        child: Text(location),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedStockLocationFilter = value;
                    });
                  },
                ),
              ],
            ),
          ),
          
          // Results count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_filteredLocations.length} plant${_filteredLocations.length != 1 ? 's' : ''} found',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadPlantLocations,
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
                                onPressed: _loadPlantLocations,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredLocations.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'No plant locations found'
                                      : 'No results found for "$_searchQuery"',
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
                            itemCount: _filteredLocations.length,
                            itemBuilder: (context, index) {
                              final location = _filteredLocations[index];
                              final plantNo = location['small_plant_no'] as String? ?? 'Unknown';
                              final stockLocation = location['stock_location'] as String? ?? 'Unknown';
                              final date = location['date'] as String?;
                              final userName = location['user_name'] as String? ?? 'Unknown';
                              final description = location['description'] as String?;
                              final type = location['type'] as String?;
                              final makeModel = location['make_model'] as String?;
                              
                              DateTime? dateTime;
                              if (date != null) {
                                try {
                                  dateTime = DateTime.parse(date);
                                } catch (e) {
                                  // Invalid date format
                                }
                              }
                              
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 2,
                                child: ExpansionTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.blue,
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
                                        'Location: $stockLocation',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      if (dateTime != null)
                                        Text(
                                          'Last checked: ${_formatDate(dateTime)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                    ],
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
                                          if (type != null) ...[
                                            _buildInfoRow('Type', type),
                                            const SizedBox(height: 8),
                                          ],
                                          if (makeModel != null) ...[
                                            _buildInfoRow('Make/Model', makeModel),
                                            const SizedBox(height: 8),
                                          ],
                                          _buildInfoRow('Stock Location', stockLocation),
                                          const SizedBox(height: 8),
                                          _buildInfoRow('Last Checked By', userName),
                                          if (dateTime != null) ...[
                                            const SizedBox(height: 8),
                                            _buildInfoRow('Last Checked Date', _formatDate(dateTime)),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

