import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';

import 'package:hatchaudit/widgets/status_badge.dart';
import 'package:hatchaudit/features/customers/screens/audit_detail_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/audits/models/audit_filter.dart';
import 'package:hatchaudit/features/audits/widgets/audit_filter_sheet.dart';
import 'package:hatchaudit/features/audits/providers/audit_session_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_session_screen.dart';

class AuditsScreen extends StatefulWidget {
  const AuditsScreen({super.key});

  @override
  State<AuditsScreen> createState() => _AuditsScreenState();
}

class _AuditsScreenState extends State<AuditsScreen> {
  static const int _pageSize = 50;

  final AuditRepository _auditRepository = AuditRepository();
  final AuditSessionRepository _sessionRepository = AuditSessionRepository();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  AuditFilter _filter = AuditFilter.empty;
  List<AuditModel> _loadedAudits = [];
  List<AuditSessionModel> _loadedSessions = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAudits();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canEditAudits ?? false,
    );

    return Scaffold(
      appBar: GradientAppBar(
        title: 'Audits',
        actions: [
          IconButton(
            tooltip: 'Filter audits',
            icon: Badge(
              isLabelVisible: _filter.hasFilters,
              label: Text(_activeFilterCount.toString()),
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _openFilters,
          ),
        ],
      ),
      body: Consumer<CustomersProvider>(
        builder: (context, provider, child) {
          if (_isInitialLoading || provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              _buildSearchBar(),
              Expanded(child: _buildAuditList(provider, canEdit: canEdit)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search audits...',
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
      ),
    );
  }

  Widget _buildAuditList(CustomersProvider provider, {required bool canEdit}) {
    final groups = _filterAuditGroups(provider);
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final hasSessions = _loadedSessions.isNotEmpty;

    if (groups.isEmpty && !hasSessions) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              hasSearch
                  ? 'No audits or visits match your search'
                  : 'No audits or visits yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Try another customer, flock, setter, or hatcher'
                  : 'Completed audits and hatchery visits will appear here',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider
          .loadCustomers(currentUser: context.read<AuthProvider>().user)
          .then((_) => _refreshAudits()),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        itemCount: _totalItemCount(hasSessions, groups),
        itemBuilder: (context, index) {
          if (hasSessions && index <= _sessionItemCount) {
            return _buildSessionTile(index);
          }

          final adjustedIndex =
              index - _sessionItemCount - (hasSessions ? 1 : 0);
          final groupIndex = _groupIndexForItem(adjustedIndex, groups);
          if (groupIndex < 0) {
            return _buildPaginationFooter();
          }

          final group = groups[groupIndex];
          final auditIndexInGroup =
              adjustedIndex - _itemOffsetForGroup(groupIndex, groups);

          if (auditIndexInGroup < 0) {
            return Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: _CustomerGroupHeader(group: group),
            );
          }

          if (auditIndexInGroup >= group.audits.length) {
            return _buildPaginationFooter();
          }

          final audit = group.audits[auditIndexInGroup];
          final flock = provider.flockById(audit.flockId);
          return Padding(
            padding: EdgeInsets.only(
              bottom: auditIndexInGroup == group.audits.length - 1 ? 0 : 12,
            ),
            child: _AuditCard(
              audit: audit,
              flockLabel: flock?.flockId ?? audit.flockId ?? '--',
              breed: flock?.breed ?? audit.soBreed ?? audit.hoBreed,
              ageWeeks: flock?.currentAgeWeeks.round(),
              canEdit: canEdit,
              onTap: () => _openAuditDetail(audit),
              onEdit: () => _editAudit(audit),
              onDelete: () => _confirmDeleteAudit(audit),
            ),
          );
        },
      ),
    );
  }

  int get _sessionItemCount => _loadedSessions.take(5).length;

  int _totalItemCount(bool hasSessions, List<_AuditCustomerGroup> groups) {
    var count = 0;
    if (hasSessions) {
      count += _sessionItemCount + 1; // sessions + section header
    }
    for (final group in groups) {
      count += 1 + group.audits.length; // header + audits
    }
    count += 1; // pagination footer
    return count;
  }

  int _groupIndexForItem(int adjustedIndex, List<_AuditCustomerGroup> groups) {
    var offset = 0;
    for (var i = 0; i < groups.length; i++) {
      if (adjustedIndex == offset) return i;
      offset += 1 + groups[i].audits.length;
      if (adjustedIndex < offset) return i;
    }
    return -1;
  }

  int _itemOffsetForGroup(int groupIndex, List<_AuditCustomerGroup> groups) {
    var offset = 0;
    for (var i = 0; i < groupIndex; i++) {
      offset += 1 + groups[i].audits.length;
    }
    return offset;
  }

  Widget _buildSessionTile(int index) {
    if (index == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const Icon(Icons.route, color: AppColors.primary, size: 18),
            const SizedBox(width: 6),
            Text(
              'Recent Visits',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      );
    }

    final session = _loadedSessions[index - 1];
    final customerName = _customerNameForSession(session);
    final isCompleted = session.status == 'completed';
    final completedCount = session.stationsCompleted.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openSession(session),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? AppColors.completedText.withValues(alpha: 0.1)
                          : AppColors.ageBadgeBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isCompleted ? 'Completed' : 'In Progress',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCompleted
                            ? AppColors.completedText
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      customerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$completedCount/5 stations',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _formatSessionDate(session.date),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _customerNameForSession(AuditSessionModel session) {
    final provider = context.read<CustomersProvider>();
    return provider.customerById(session.customerId)?.name ??
        session.customerId;
  }

  String _formatSessionDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')} '
        '${_monthAbbreviation(date.month)} '
        '${date.year}';
  }

  String _monthAbbreviation(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Future<void> _openSession(AuditSessionModel session) async {
    if (session.status == 'in_progress') {
      final sessionProvider = context.read<AuditSessionProvider>();
      await sessionProvider.resumeSession(session.id);

      if (!mounted) return;
      if (sessionProvider.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(sessionProvider.error!)));
        return;
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChangeNotifierProvider.value(
            value: sessionProvider,
            child: const AuditSessionScreen(),
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _SessionDetailScreen(session: session),
        ),
      );
    }

    if (mounted) {
      await _refreshAudits();
    }
  }

  List<_AuditCustomerGroup> _filterAuditGroups(CustomersProvider provider) {
    final query = _searchQuery.trim().toLowerCase();
    final grouped = <String, List<AuditModel>>{};

    for (final audit in _loadedAudits) {
      final customer = provider.customerById(audit.customerId);
      final customerName = customer?.name ?? audit.customerId;
      final customerMatches =
          query.isEmpty ||
          _matchesQuery(customerName, query) ||
          _matchesQuery(audit.customerId, query);
      final auditMatches = _auditMatchesQuery(audit, provider, query);
      if (query.isNotEmpty && !customerMatches && !auditMatches) continue;
      grouped.putIfAbsent(audit.customerId, () => <AuditModel>[]).add(audit);
    }

    final groups = grouped.entries.map((entry) {
      final customer = provider.customerById(entry.key);
      final audits = entry.value..sort((a, b) => b.date.compareTo(a.date));
      return _AuditCustomerGroup(
        customerName: customer?.name ?? entry.key,
        audits: audits,
      );
    }).toList();

    return groups..sort((a, b) {
      final dateSort = b.latestDate.compareTo(a.latestDate);
      if (dateSort != 0) return dateSort;
      return a.customerName.toLowerCase().compareTo(
        b.customerName.toLowerCase(),
      );
    });
  }

  bool _auditMatchesQuery(
    AuditModel audit,
    CustomersProvider provider,
    String query,
  ) {
    if (query.isEmpty) return true;
    final flock = provider.flockById(audit.flockId);
    return _matchesQuery(audit.flockId, query) ||
        _matchesQuery(flock?.flockId, query) ||
        _matchesQuery(flock?.breed, query) ||
        _matchesQuery(audit.auditType, query) ||
        _matchesQuery(audit.setterId, query) ||
        _matchesQuery(audit.soSetterId, query) ||
        _matchesQuery(audit.hatcherId, query) ||
        _matchesQuery(audit.hoHatcherId, query) ||
        _matchesQuery(audit.status, query) ||
        _matchesQuery(audit.date.toIso8601String().split('T')[0], query);
  }

  bool _matchesQuery(String? value, String query) {
    return value?.toLowerCase().contains(query) ?? false;
  }

  Future<void> _openAuditDetail(AuditModel audit) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (context) => AuditDetailScreen(audit: audit)),
    );
    if (!mounted) return;
    await _refreshAudits();
  }

  Future<void> _editAudit(AuditModel audit) async {
    await openAuditEditor(context, audit);
    if (!mounted) return;
    await _refreshAudits();
  }

  Future<void> _confirmDeleteAudit(AuditModel audit) async {
    final provider = context.read<CustomersProvider>();
    final customerName = provider.customerById(audit.customerId)?.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove audit?'),
        content: Text(
          'This removes the ${audit.auditType} audit'
          '${customerName == null ? '' : ' for $customerName'} and its linked photos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    try {
      await context.read<CustomersProvider>().deleteAudit(audit.id);
      await _refreshAudits();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Audit removed')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not remove audit: $error')));
    }
  }

  Future<void> _refreshAudits() async {
    if (mounted) {
      setState(() {
        _isInitialLoading = true;
        _loadedAudits = [];
        _loadedSessions = [];
        _page = 0;
        _hasMore = true;
      });
    }

    final currentUser = context.read<AuthProvider>().user;
    await context.read<CustomersProvider>().loadCustomers(
      currentUser: currentUser,
    );

    final auditsFuture = _fetchPage(page: 0);
    final sessionsFuture =
        currentUser?.isCustomer == true && currentUser?.customerId != null
        ? _sessionRepository.getSessionsByCustomer(
            currentUser!.customerId!,
            limit: 50,
          )
        : _sessionRepository.getAllSessions(limit: 50);

    final results = await Future.wait([auditsFuture, sessionsFuture]);

    if (!mounted) return;
    setState(() {
      _loadedAudits = results[0] as List<AuditModel>;
      _loadedSessions = results[1] as List<AuditSessionModel>;
      _page = 1;
      _hasMore = _loadedAudits.length == _pageSize;
      _isInitialLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    final rows = await _fetchPage(page: _page);
    if (!mounted) return;
    setState(() {
      _loadedAudits.addAll(rows);
      _page += 1;
      _hasMore = rows.length == _pageSize;
      _isLoadingMore = false;
    });
  }

  Future<List<AuditModel>> _fetchPage({required int page}) {
    final currentUser = context.read<AuthProvider>().user;
    final customerId = currentUser?.isCustomer == true
        ? currentUser?.customerId
        : null;
    final effectiveFilter = customerId == null
        ? _filter
        : _filter.copyWith(customerId: customerId);
    if (effectiveFilter.hasFilters) {
      return _auditRepository.getFilteredAudits(
        effectiveFilter,
        limit: _pageSize,
        offset: page * _pageSize,
      );
    }
    return _auditRepository.getAllAudits(
      limit: _pageSize,
      offset: page * _pageSize,
      customerId: customerId,
    );
  }

  int get _activeFilterCount {
    var count = 0;
    if (_filter.dateFrom != null || _filter.dateTo != null) count++;
    if (_filter.auditTypes.isNotEmpty) count++;
    if (_filter.customerId != null) count++;
    if (_filter.flockId != null) count++;
    if (_filter.status != null) count++;
    return count;
  }

  Future<void> _openFilters() async {
    final nextFilter = await showModalBottomSheet<AuditFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AuditFilterSheet(initialFilter: _filter),
    );
    if (!mounted || nextFilter == null) return;
    setState(() => _filter = nextFilter);
    await _refreshAudits();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Widget _buildPaginationFooter() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasMore && _loadedAudits.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'All audits loaded',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }
    return const SizedBox(height: 16);
  }
}

class _CustomerGroupHeader extends StatelessWidget {
  final _AuditCustomerGroup group;

  const _CustomerGroupHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    final auditLabel = group.audits.length == 1 ? 'audit' : 'audits';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.customerName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F2937),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.ageBadgeBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${group.audits.length} $auditLabel',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  final AuditModel audit;
  final String flockLabel;
  final String? breed;
  final int? ageWeeks;
  final bool canEdit;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AuditCard({
    required this.audit,
    required this.flockLabel,
    required this.breed,
    required this.ageWeeks,
    required this.canEdit,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildAgeBadge(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      audit.auditType,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusBadge(status: audit.status),
                  if (canEdit) ...[
                    const SizedBox(width: 4),
                    PopupMenuButton<_AuditAction>(
                      tooltip: 'Audit actions',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (action) {
                        switch (action) {
                          case _AuditAction.edit:
                            onEdit();
                            break;
                          case _AuditAction.delete:
                            onDelete();
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _AuditAction.edit,
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit audit'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: _AuditAction.delete,
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Remove audit'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$flockLabel${breed != null ? ' · $breed' : ''} · ${audit.date.toString().split(' ')[0]}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (_equipmentLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _equipmentLine,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ageBadgeBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        ageWeeks != null ? '${ageWeeks}w' : '--',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  String get _equipmentLine {
    final setter = audit.setterId ?? audit.soSetterId;
    final hatcher = audit.hatcherId ?? audit.hoHatcherId;
    return [
      if (setter != null) 'Setter $setter',
      if (hatcher != null) 'Hatcher $hatcher',
    ].join(' · ');
  }
}

class _AuditCustomerGroup {
  final String customerName;
  final List<AuditModel> audits;

  const _AuditCustomerGroup({required this.customerName, required this.audits});

  DateTime get latestDate => audits.first.date;
}

enum _AuditAction { edit, delete }

class _SessionDetailScreen extends StatelessWidget {
  final AuditSessionModel session;

  const _SessionDetailScreen({required this.session});

  @override
  Widget build(BuildContext context) {
    final stationLabels = const [
      'Egg Storage',
      'Chick Quality',
      'Hatch Analysis',
      'Setter Optimizing',
      'Hatcher Optimizing',
    ];

    return Scaffold(
      appBar: const GradientAppBar(title: 'Visit Details'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 16),
          Text(
            'Station Progress',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(stationLabels.length, (index) {
            final isCompleted = session.stationsCompleted.contains(
              supportedStationKeys[index],
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _StationProgressTile(
                number: index + 1,
                label: stationLabels[index],
                isCompleted: isCompleted,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      elevation: 0,
      color: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hatchery Visit',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(session.date),
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: session.status == 'completed'
                        ? AppColors.completedText.withValues(alpha: 0.1)
                        : AppColors.ageBadgeBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    session.status == 'completed' ? 'Completed' : 'In Progress',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: session.status == 'completed'
                          ? AppColors.completedText
                          : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoPill(label: 'Customer', value: session.customerId),
                if (session.breed != null)
                  _InfoPill(label: 'Breed', value: session.breed!),
                _InfoPill(
                  label: 'Stations',
                  value: '${session.stationsCompleted.length}/5',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')} '
        '${_monthAbbreviation(date.month)} '
        '${date.year}';
  }

  String _monthAbbreviation(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

class _StationProgressTile extends StatelessWidget {
  final int number;
  final String label;
  final bool isCompleted;

  const _StationProgressTile({
    required this.number,
    required this.label,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCompleted
              ? AppColors.completedText.withValues(alpha: 0.3)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? AppColors.completedText
                  : Colors.grey.shade300,
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isCompleted ? FontWeight.w600 : FontWeight.w500,
                color: isCompleted
                    ? AppColors.completedText
                    : const Color(0xFF1F2937),
              ),
            ),
          ),
          if (isCompleted)
            const Icon(
              Icons.check_circle,
              color: AppColors.completedText,
              size: 18,
            ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: Colors.black87),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
