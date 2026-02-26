import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../modules/database/database_service.dart';
import '../modules/users/user_service.dart';
import '../config/supabase_config.dart';
import '../widgets/screen_info_icon.dart';
import 'timesheet_screen.dart';
import 'my_time_periods_screen.dart';
import 'asset_check_screen.dart';
import 'delivery_screen.dart';

/// My Dashboard Screen
/// 
/// Unified dashboard showing user's recent activity across all modules.
/// Allows quick navigation to relevant screens.
class MyDashboardScreen extends StatefulWidget {
  const MyDashboardScreen({super.key});

  @override
  State<MyDashboardScreen> createState() => _MyDashboardScreenState();
}

class _MyDashboardScreenState extends State<MyDashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userSetup;
  Map<String, dynamic>? _userData;
  
  // Dashboard data
  int _timePeriodsCount = 0;
  int _assetChecksCount = 0;
  int _deliveriesCount = 0;
  List<Map<String, dynamic>> _recentTimePeriods = [];
  DateTime? _lastClockIn;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load user setup and data
      _userSetup = await UserService.getCurrentUserSetup();
      _userData = await UserService.getCurrentUserData();
      
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Load time periods count (last 30 days) - active only
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final allTimePeriodsRaw = await SupabaseService.client
          .from('time_periods')
          .select()
          .eq('user_id', userId)
          .eq('is_active', true);
      final allTimePeriods = List<Map<String, dynamic>>.from(allTimePeriodsRaw as List);

      // Filter by date (last 30 days)
      final timePeriods = allTimePeriods.where((tp) {
        final workDate = tp['work_date'];
        if (workDate == null) return false;
        final date = workDate is DateTime 
            ? workDate 
            : DateTime.tryParse(workDate.toString());
        return date != null && date.isAfter(thirtyDaysAgo);
      }).toList();
      
      _timePeriodsCount = timePeriods.length;
      
      // Get recent time periods (last 5)
      _recentTimePeriods = timePeriods
          .take(5)
          .toList();
      
      // Load asset checks count (last 30 days)
      // Note: Adjust table name if different
      try {
        final allAssetChecks = await DatabaseService.read(
          'asset_checks',
          filterColumn: 'user_id',
          filterValue: userId,
        );
        // Filter by date if needed (assuming there's a created_at or similar field)
        _assetChecksCount = allAssetChecks.length;
      } catch (e) {
        // Table might not exist yet
        _assetChecksCount = 0;
      }
      
      // Load deliveries count (last 30 days)
      // Note: Adjust table name if different
      try {
        final allDeliveries = await DatabaseService.read(
          'deliveries',
          filterColumn: 'user_id',
          filterValue: userId,
        );
        // Filter by date if needed (assuming there's a created_at or similar field)
        _deliveriesCount = allDeliveries.length;
      } catch (e) {
        // Table might not exist yet
        _deliveriesCount = 0;
      }

    } catch (e) {
      print('❌ Error loading dashboard data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Dashboard',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'my_dashboard_screen.dart')],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome section
                    _buildWelcomeSection(),
                    const SizedBox(height: 24),
                    
                    // Quick stats
                    _buildQuickStats(),
                    const SizedBox(height: 24),
                    
                    // Recent activity
                    _buildRecentActivity(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildWelcomeSection() {
    final displayName = _userSetup?['display_name'] ?? 
                       _userData?['display_name'] ?? 
                       'User';
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFF0081FB),
              child: Text(
                displayName.toString().substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back,',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayName.toString(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
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

  Widget _buildQuickStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Stats (Last 30 Days)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Time Periods',
                _timePeriodsCount.toString(),
                Icons.access_time,
                Colors.blue,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MyTimePeriodsScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Asset Checks',
                _assetChecksCount.toString(),
                Icons.check_circle,
                Colors.orange,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AssetCheckScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Deliveries',
                _deliveriesCount.toString(),
                Icons.local_shipping,
                Colors.teal,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DeliveryScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Time Periods',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyTimePeriodsScreen(),
                  ),
                );
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_recentTimePeriods.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text(
                  'No recent time periods',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          )
        else
          ..._recentTimePeriods.map((period) => _buildTimePeriodCard(period)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TimeTrackingScreen(),
              ),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('New Time Period'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  Widget _buildTimePeriodCard(Map<String, dynamic> period) {
    final workDate = period['work_date'];
    DateTime? date;
    if (workDate != null) {
      date = workDate is DateTime 
          ? workDate 
          : DateTime.tryParse(workDate.toString());
    }
    
    final dateStr = date != null 
        ? DateFormat('MMM dd, yyyy').format(date)
        : 'Unknown date';
    
    final status = period['status']?.toString() ?? 'unknown';
    final statusColor = _getStatusColor(status);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          child: Icon(
            _getStatusIcon(status),
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text(dateStr),
        subtitle: Text('Status: ${status.toUpperCase()}'),
        trailing: IconButton(
          icon: const Icon(Icons.arrow_forward_ios, size: 16),
          onPressed: () {
            // Navigate to edit if submitted, view if approved
            if (status == 'submitted') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TimeTrackingScreen(
                    timePeriodId: period['id']?.toString(),
                  ),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MyTimePeriodsScreen(),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'submitted':
        return Colors.orange;
      case 'supervisor_approved':
      case 'admin_approved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'submitted':
        return Icons.pending;
      case 'supervisor_approved':
      case 'admin_approved':
        return Icons.check_circle;
      default:
        return Icons.info;
    }
  }
}
