/// My Checks Screen
/// 
/// Displays all Large Plant and Small Plant checks submitted by the user,
/// summarized per week period

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:intl/intl.dart';
import '../config/supabase_config.dart';
import '../modules/auth/auth_service.dart';
import '../modules/database/database_service.dart';
import '../modules/errors/error_log_service.dart';

class MyChecksScreen extends StatefulWidget {
  const MyChecksScreen({super.key});

  @override
  State<MyChecksScreen> createState() => _MyChecksScreenState();
}

class _MyChecksScreenState extends State<MyChecksScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _weeklySummaries = [];
  String _errorMessage = '';
  // Week start from system_settings: 0-6 (PostgreSQL DOW: 0=Sunday .. 6=Saturday)
  int _weekStartDow = 1;

  @override
  void initState() {
    super.initState();
    _loadWeekStart();
    _loadChecks();
  }

  Future<void> _loadWeekStart() async {
    try {
      final response = await SupabaseService.client
          .from('system_settings')
          .select('week_start')
          .limit(1)
          .maybeSingle();
      if (response != null) {
        final v = int.tryParse(response['week_start']?.toString() ?? '');
        if (v != null && v >= 0 && v <= 6) setState(() => _weekStartDow = v);
      }
    } catch (e) {
      print('⚠️ Error loading week start: $e');
    }
  }

  DateTime _getWeekStart(DateTime date) {
    final w = _weekStartDow == 0 ? 7 : _weekStartDow;
    final daysToSubtract = (date.weekday - w + 7) % 7;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: daysToSubtract));
  }

  Future<void> _loadChecks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final userId = AuthService.getCurrentUser()?.id;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // small_plant_check: eq user_id uses idx_small_plant_check_user_id (see supabase_indexes.md)
      final smallPlantChecks = await SupabaseService.client
          .from('small_plant_check')
          .select('id, date, stock_location, small_plant_no, created_at')
          .eq('user_id', userId)
          .order('date', ascending: false);

      // Group by week
      final Map<String, Map<String, dynamic>> weekMap = {};
      
      for (final check in smallPlantChecks) {
        final dateStr = check['date']?.toString();
        if (dateStr == null) continue;
        
        try {
          final date = DateTime.parse(dateStr);
          final weekStart = _getWeekStart(date);
          final weekKey = DateFormat('yyyy-MM-dd').format(weekStart);
          
          if (!weekMap.containsKey(weekKey)) {
            weekMap[weekKey] = {
              'week_start': weekStart,
              'week_key': weekKey,
              'small_plant_checks': <Map<String, dynamic>>[],
              'large_plant_checks': <Map<String, dynamic>>[], // Placeholder for future
            };
          }
          
          weekMap[weekKey]!['small_plant_checks'].add(check);
        } catch (e) {
          print('⚠️ Error parsing date: $dateStr - $e');
        }
      }

      // Convert to list and sort by week_start (descending)
      final summaries = weekMap.values.toList();
      summaries.sort((a, b) {
        final aStart = a['week_start'] as DateTime;
        final bStart = b['week_start'] as DateTime;
        return bStart.compareTo(aStart);
      });

      setState(() {
        _weeklySummaries = summaries;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'My Checks Screen - Load',
        type: 'Database',
        description: 'Failed to load checks: $e',
        stackTrace: stackTrace,
      );
      
      setState(() {
        _errorMessage = 'Failed to load checks: $e';
        _isLoading = false;
      });
    }
  }

  String _formatWeekRange(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    return '${DateFormat('d MMM').format(weekStart)} - ${DateFormat('d MMM yyyy').format(weekEnd)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Checks',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: [
          const ScreenInfoIcon(screenName: 'my_checks_screen.dart'),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChecks,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
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
                          onPressed: _loadChecks,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _weeklySummaries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No checks found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _weeklySummaries.length,
                      itemBuilder: (context, index) {
                        final summary = _weeklySummaries[index];
                        final weekStart = summary['week_start'] as DateTime;
                        final weekKey = summary['week_key'] as String;
                        final smallPlantChecks = summary['small_plant_checks'] as List<Map<String, dynamic>>;
                        final largePlantChecks = summary['large_plant_checks'] as List<Map<String, dynamic>>;
                        
                        final totalSmall = smallPlantChecks.length;
                        final totalLarge = largePlantChecks.length;
                        final total = totalSmall + totalLarge;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          elevation: 2,
                          child: ExpansionTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.calendar_today,
                                color: Colors.blue,
                              ),
                            ),
                            title: Text(
                              _formatWeekRange(weekStart),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              '$total check${total != 1 ? 's' : ''} (${totalSmall} Small Plant${totalSmall != 1 ? '' : ''}, ${totalLarge} Large Plant${totalLarge != 1 ? '' : ''})',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            children: [
                              if (totalSmall > 0) ...[
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.construction, size: 20, color: Colors.blue),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Small Plant Checks ($totalSmall)',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      ...smallPlantChecks.map((check) {
                                        final dateStr = check['date']?.toString() ?? '';
                                        final stockLocation = check['stock_location']?.toString() ?? 'Unknown';
                                        final plantNo = check['small_plant_no']?.toString() ?? 'Unknown';
                                        final createdAt = check['created_at']?.toString();
                                        
                                        DateTime? date;
                                        DateTime? created;
                                        try {
                                          if (dateStr.isNotEmpty) {
                                            date = DateTime.parse(dateStr);
                                          }
                                          if (createdAt != null && createdAt.isNotEmpty) {
                                            created = DateTime.parse(createdAt);
                                          }
                                        } catch (e) {
                                          // Invalid date format
                                        }

                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[50],
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey[300]!),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    plantNo,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  if (date != null)
                                                    Text(
                                                      DateFormat('d MMM yyyy').format(date),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Location: $stockLocation',
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                              if (created != null) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Submitted: ${DateFormat('d MMM yyyy HH:mm').format(created)}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                ),
                              ],
                              if (totalLarge > 0) ...[
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.local_shipping, size: 20, color: Colors.green),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Large Plant Checks ($totalLarge)',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Large plant checks will be displayed here when implemented.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
