/// Recipient Selection Screen
/// 
/// Allows users to select multiple recipients by:
/// - Individual users
/// - Roles
/// - Security levels
/// Supports filtering and search functionality.

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import '../modules/users/user_edit_service.dart';
import '../modules/users/user_service.dart';
import '../modules/database/database_service.dart';
import '../modules/errors/error_log_service.dart';

class RecipientSelectionScreen extends StatefulWidget {
  final List<String>? initialSelectedUserIds;
  final List<String>? initialSelectedRoles;
  final List<int>? initialSelectedSecurityLevels;

  const RecipientSelectionScreen({
    super.key,
    this.initialSelectedUserIds,
    this.initialSelectedRoles,
    this.initialSelectedSecurityLevels,
  });

  @override
  State<RecipientSelectionScreen> createState() => _RecipientSelectionScreenState();
}

class _RecipientSelectionScreenState extends State<RecipientSelectionScreen> {
  // Selected recipients
  Set<String> _selectedUserIds = {};
  Set<String> _selectedRoles = {};
  Set<int> _selectedSecurityLevels = {};

  // Data lists
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoadingUsers = false;

  // Filtering
  final _userSearchController = TextEditingController();
  String? _selectedRoleFilter;
  int? _selectedSecurityFilter;

  // Tab selection
  int _currentTab = 0; // 0 = Users, 1 = Roles, 2 = Security

  @override
  void initState() {
    super.initState();
    // Initialize with provided selections
    if (widget.initialSelectedUserIds != null) {
      _selectedUserIds = Set<String>.from(widget.initialSelectedUserIds!);
    }
    if (widget.initialSelectedRoles != null) {
      _selectedRoles = Set<String>.from(widget.initialSelectedRoles!);
    }
    if (widget.initialSelectedSecurityLevels != null) {
      _selectedSecurityLevels = Set<int>.from(widget.initialSelectedSecurityLevels!);
    }
    _loadUsers();
  }

  @override
  void dispose() {
    _userSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final users = await UserEditService.getAllUsers();
      setState(() {
        _allUsers = users;
        _filteredUsers = users;
        _isLoadingUsers = false;
      });
      _applyUserFilters();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Recipient Selection Screen - Load Users',
        type: 'Database',
        description: 'Failed to load users: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _isLoadingUsers = false;
      });
    }
  }

  void _applyUserFilters() {
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        // Search filter
        final searchTerm = _userSearchController.text.toLowerCase();
        if (searchTerm.isNotEmpty) {
          final displayName = (user['display_name']?.toString() ?? '').toLowerCase();
          final forename = (user['forename']?.toString() ?? '').toLowerCase();
          final surname = (user['surname']?.toString() ?? '').toLowerCase();
          if (!displayName.contains(searchTerm) &&
              !forename.contains(searchTerm) &&
              !surname.contains(searchTerm)) {
            return false;
          }
        }

        // Role filter
        if (_selectedRoleFilter != null) {
          // Get role from users_setup if available
          // For now, we'll need to fetch this separately or skip role filtering
          // This is a simplified version - you may need to enhance based on your schema
        }

        // Security filter
        if (_selectedSecurityFilter != null) {
          final userSecurity = user['users_setup']?['security'] as int?;
          if (userSecurity != _selectedSecurityFilter) {
            return false;
          }
        }

        return true;
      }).toList();
    });
  }

  void _toggleUserSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  void _toggleRoleSelection(String role) {
    setState(() {
      if (_selectedRoles.contains(role)) {
        _selectedRoles.remove(role);
      } else {
        _selectedRoles.add(role);
      }
    });
  }

  void _toggleSecuritySelection(int level) {
    setState(() {
      if (_selectedSecurityLevels.contains(level)) {
        _selectedSecurityLevels.remove(level);
      } else {
        _selectedSecurityLevels.add(level);
      }
    });
  }

  void _selectAllUsers() {
    setState(() {
      if (_selectedUserIds.length == _filteredUsers.length) {
        _selectedUserIds.clear();
      } else {
        _selectedUserIds = _filteredUsers
            .map((u) => u['user_id']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toSet();
      }
    });
  }

  void _selectAllRoles() {
    setState(() {
      if (_selectedRoles.length == UserService.validRoles.length) {
        _selectedRoles.clear();
      } else {
        _selectedRoles = UserService.validRoles.toSet();
      }
    });
  }

  void _selectAllSecurityLevels() {
    setState(() {
      if (_selectedSecurityLevels.length == 9) {
        _selectedSecurityLevels.clear();
      } else {
        _selectedSecurityLevels = {1, 2, 3, 4, 5, 6, 7, 8, 9};
      }
    });
  }

  void _confirmSelection() {
    Navigator.pop(context, {
      'userIds': _selectedUserIds.toList(),
      'roles': _selectedRoles.toList(),
      'securityLevels': _selectedSecurityLevels.toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Recipients', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'recipient_selection_screen.dart')],
      ),
      body: Column(
        children: [
          // Tab selection
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(0, 'Users', _selectedUserIds.length),
                ),
                Expanded(
                  child: _buildTabButton(1, 'Roles', _selectedRoles.length),
                ),
                Expanded(
                  child: _buildTabButton(2, 'Security', _selectedSecurityLevels.length),
                ),
              ],
            ),
          ),

          // Content area
          Expanded(
            child: IndexedStack(
              index: _currentTab,
              children: [
                _buildUsersTab(),
                _buildRolesTab(),
                _buildSecurityTab(),
              ],
            ),
          ),

          // Summary and confirm button
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryChip('Users', _selectedUserIds.length),
                    _buildSummaryChip('Roles', _selectedRoles.length),
                    _buildSummaryChip('Security', _selectedSecurityLevels.length),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: (_selectedUserIds.isEmpty &&
                          _selectedRoles.isEmpty &&
                          _selectedSecurityLevels.isEmpty)
                      ? null
                      : _confirmSelection,
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm Selection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, int count) {
    final isSelected = _currentTab == index;
    return InkWell(
      onTap: () => setState(() => _currentTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0081FB) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.yellow : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.yellow : Colors.grey[400],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTab() {
    return Column(
      children: [
        // Search and filters
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _userSearchController,
                decoration: InputDecoration(
                  labelText: 'Search Users',
                  hintText: 'Enter name to search...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _userSearchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _userSearchController.clear();
                            _applyUserFilters();
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => _applyUserFilters(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedSecurityFilter,
                      decoration: const InputDecoration(
                        labelText: 'Filter by Security',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All')),
                        ...List.generate(9, (i) {
                          final level = i + 1;
                          return DropdownMenuItem(
                            value: level,
                            child: Text('Level $level'),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedSecurityFilter = value);
                        _applyUserFilters();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _selectAllUsers,
                    icon: Icon(
                      _selectedUserIds.length == _filteredUsers.length
                          ? Icons.deselect
                          : Icons.select_all,
                    ),
                    label: Text(
                      _selectedUserIds.length == _filteredUsers.length
                          ? 'Deselect All'
                          : 'Select All',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // User list
        Expanded(
          child: _isLoadingUsers
              ? const Center(child: CircularProgressIndicator())
              : _filteredUsers.isEmpty
                  ? const Center(child: Text('No users found'))
                  : ListView.builder(
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        final userId = user['user_id']?.toString() ?? '';
                        final displayName = user['display_name']?.toString() ?? 'Unknown';
                        final security = user['users_setup']?['security'] as int?;
                        final isSelected = _selectedUserIds.contains(userId);

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (_) => _toggleUserSelection(userId),
                          title: Text(displayName),
                          subtitle: security != null
                              ? Text('Security Level: $security')
                              : null,
                          secondary: CircleAvatar(
                            child: Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildRolesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: _selectAllRoles,
            icon: Icon(
              _selectedRoles.length == UserService.validRoles.length
                  ? Icons.deselect
                  : Icons.select_all,
            ),
            label: Text(
              _selectedRoles.length == UserService.validRoles.length
                  ? 'Deselect All Roles'
                  : 'Select All Roles',
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: UserService.validRoles.length,
            itemBuilder: (context, index) {
              final role = UserService.validRoles[index];
              final isSelected = _selectedRoles.contains(role);

              return CheckboxListTile(
                value: isSelected,
                onChanged: (_) => _toggleRoleSelection(role),
                title: Text(role),
                secondary: const Icon(Icons.badge),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: _selectAllSecurityLevels,
            icon: Icon(
              _selectedSecurityLevels.length == 9 ? Icons.deselect : Icons.select_all,
            ),
            label: Text(
              _selectedSecurityLevels.length == 9
                  ? 'Deselect All Levels'
                  : 'Select All Levels',
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: 9,
            itemBuilder: (context, index) {
              final level = index + 1;
              final isSelected = _selectedSecurityLevels.contains(level);
              final levelLabel = level == 1
                  ? 'Level $level (Admin)'
                  : level == 9
                      ? 'Level $level (Visitor)'
                      : 'Level $level';

              return CheckboxListTile(
                value: isSelected,
                onChanged: (_) => _toggleSecuritySelection(level),
                title: Text(levelLabel),
                secondary: Icon(
                  Icons.security,
                  color: level <= 3 ? Colors.red : Colors.blue,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryChip(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$label: $count',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
