import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/debug/startup_timer.dart';
import '../../../core/navigation/shell_navigation_scope.dart';
import '../../../data/models/user_model.dart';
import '../../../providers/customers_provider.dart';
import '../../../services/sync/app_sync_coordinator.dart';
import '../../../services/sync/bg_sync_service.dart';
import '../../../widgets/chick_mark_logo.dart';
import '../../auth/providers/auth_provider.dart';
import '../../agents/providers/agent_monitor_provider.dart';
import '../../agents/screens/agent_monitor_screen.dart';
import '../../home/screens/home_screen.dart';
import '../../settings/providers/settings_provider.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../customers/screens/customers_screen.dart';
import '../../audits/screens/audits_screen.dart';
import '../../govee/screens/govee_records_screen.dart';
import '../../lab_analysis/screens/lab_analysis_screen.dart';
import '../../bmk/screens/bmk_screen.dart';
import '../../settings/screens/settings_screen.dart';

const _allMainShellTabKeys = <String>[
  'home',
  'dashboard',
  'customers',
  'audits',
  'govee',
  'lab_analysis',
  'bmk',
  'agent',
  'settings',
];

const _customerMainShellTabKeys = <String>{'dashboard', 'settings'};

List<String> mainShellTabKeysForUser(UserModel? user) {
  if (user?.isCustomer == true) {
    return _allMainShellTabKeys
        .where(_customerMainShellTabKeys.contains)
        .toList(growable: false);
  }
  return _allMainShellTabKeys
      .where(
        (key) =>
            key != 'agent' ||
            (user?.isApproved == true && user?.isAdmin == true),
      )
      .toList(growable: false);
}

@visibleForTesting
Widget buildMainShellNavigationDrawerForTest({
  required List<String> labels,
  ValueChanged<int>? onDestinationSelected,
}) {
  return _ShellNavigationDrawer(
    destinations: labels
        .map(
          (label) => _ShellDestination(
            label: label,
            icon: Icons.circle_outlined,
            selectedIcon: Icons.circle,
          ),
        )
        .toList(growable: false),
    currentIndex: 0,
    onDestinationSelected: onDestinationSelected ?? (_) {},
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final BgSyncService _bgSync = BgSyncService();
  int _currentIndex = 0;
  final List<int> _tabHistory = [];
  bool _syncConfigured = false;

  // Tabs a read-only customer is allowed to see. Agent Monitor is narrower:
  // its remote tables are admin-only, so auditors must not enter the local
  // offline mirror or create writes that RLS will reject. Settings stays so
  // customers can still reach account + sign-out.
  List<_ShellTab> _tabsFor(UserModel? user) {
    final all = <_ShellTab>[
      _ShellTab(
        'home',
        const _ShellDestination(
          label: AppStrings.homeTab,
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
        ),
        () => const HomeScreen(),
      ),
      _ShellTab(
        'dashboard',
        const _ShellDestination(
          label: AppStrings.dashboardTab,
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart,
        ),
        () => const DashboardScreen(),
      ),
      _ShellTab(
        'customers',
        const _ShellDestination(
          label: AppStrings.customersTab,
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
        ),
        () => const CustomersScreen(),
      ),
      _ShellTab(
        'audits',
        const _ShellDestination(
          label: AppStrings.auditsTab,
          icon: Icons.assignment_outlined,
          selectedIcon: Icons.assignment,
        ),
        () => const AuditsScreen(),
      ),
      _ShellTab(
        'govee',
        const _ShellDestination(
          label: AppStrings.goveeRecordsTab,
          icon: Icons.device_thermostat_outlined,
          selectedIcon: Icons.device_thermostat,
        ),
        () => const GoveeRecordsScreen(),
      ),
      _ShellTab(
        'lab_analysis',
        const _ShellDestination(
          label: AppStrings.labAnalysisTab,
          icon: Icons.biotech_outlined,
          selectedIcon: Icons.biotech,
        ),
        () => const LabAnalysisScreen(),
      ),
      _ShellTab(
        'bmk',
        const _ShellDestination(
          label: AppStrings.bmkTab,
          icon: Icons.science_outlined,
          selectedIcon: Icons.science,
        ),
        () => const BmkScreen(),
      ),
      _ShellTab(
        'agent',
        const _ShellDestination(
          label: AppStrings.agentTab,
          icon: Icons.smart_toy_outlined,
          selectedIcon: Icons.smart_toy,
        ),
        () => ChangeNotifierProvider(
          create: (_) => AgentMonitorProvider(currentUser: user),
          child: const AgentMonitorScreen(),
        ),
      ),
      _ShellTab(
        'settings',
        const _ShellDestination(
          label: AppStrings.settingsTab,
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
        ),
        () => const SettingsScreen(),
      ),
    ];
    final visibleKeys = mainShellTabKeysForUser(user).toSet();
    return all.where((tab) => visibleKeys.contains(tab.key)).toList();
  }

  late List<_ShellTab> _tabs = _tabsFor(null);
  final Map<int, Widget> _builtScreens = {};
  bool _homeLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StartupTimer.lap('main_shell_init');
  }

  @override
  void dispose() {
    AppSyncCoordinator.disable();
    WidgetsBinding.instance.removeObserver(this);
    _bgSync.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppSyncCoordinator.nudge(immediate: true);
    }
  }

  void _configureBackgroundSync() {
    if (_syncConfigured) return;
    _syncConfigured = true;
    StartupTimer.lap('bg_sync_triggering');
    final authProvider = context.read<AuthProvider>();
    final customersProvider = context.read<CustomersProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    AppSyncCoordinator.enable(
      sync: () => _bgSync.runBackgroundSync(
        authProvider: authProvider,
        customersProvider: customersProvider,
        settingsProvider: settingsProvider,
      ),
    );
    AppSyncCoordinator.nudge(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final nextTabs = _tabsFor(user);
    // If the role-visible tab set changed (e.g. role resolved after login),
    // reset to the first tab and drop cached screens that no longer apply.
    if (nextTabs.length != _tabs.length ||
        !_tabsHaveSameKeys(nextTabs, _tabs)) {
      _tabs = nextTabs;
      _builtScreens.clear();
      _tabHistory.clear();
      _currentIndex = 0;
      _homeLoaded = false;
    }
    if (_currentIndex >= _tabs.length) _currentIndex = 0;

    if (!_homeLoaded) {
      _builtScreens[_currentIndex] = _buildScreen(_currentIndex);
      _homeLoaded = true;
      StartupTimer.lap('home_screen_built');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _configureBackgroundSync();
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useNavigationRail = constraints.maxWidth >= 900;

        return Scaffold(
          key: _scaffoldKey,
          drawer: useNavigationRail
              ? null
              : _ShellNavigationDrawer(
                  destinations: _tabs.map((t) => t.destination).toList(),
                  currentIndex: _currentIndex,
                  onDestinationSelected: _selectDestination,
                ),
          body: ShellNavigationScope(
            hasDrawer: !useNavigationRail,
            openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            canGoBack: _tabHistory.isNotEmpty,
            goBack: _goBack,
            switchTab: _selectDestination,
            child: Row(
              children: [
                if (useNavigationRail)
                  _ShellNavigationRail(
                    destinations: _tabs.map((t) => t.destination).toList(),
                    currentIndex: _currentIndex,
                    onDestinationSelected: _selectDestination,
                  ),
                Expanded(child: _builtScreens[_currentIndex]!),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _tabsHaveSameKeys(List<_ShellTab> a, List<_ShellTab> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].key != b[i].key) return false;
    }
    return true;
  }

  Widget _buildScreen(int index) {
    if (index < 0 || index >= _tabs.length) return const HomeScreen();
    return _tabs[index].builder();
  }

  void _selectDestination(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (_currentIndex != index) {
      if (!_builtScreens.containsKey(index)) {
        _builtScreens[index] = _buildScreen(index);
        StartupTimer.lap('${_tabs[index].key}_tab_first_load');
      }
      setState(() {
        _tabHistory.remove(index);
        _tabHistory.add(_currentIndex);
        _currentIndex = index;
      });
    }

    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _goBack() {
    if (_tabHistory.isEmpty) return;
    setState(() {
      _currentIndex = _tabHistory.removeLast();
    });
  }
}

class _ShellTab {
  final String key;
  final _ShellDestination destination;
  final Widget Function() builder;

  const _ShellTab(this.key, this.destination, this.builder);
}

class _ShellDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class _ShellNavigationDrawer extends StatelessWidget {
  final List<_ShellDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  const _ShellNavigationDrawer({
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final drawerWidth = (MediaQuery.sizeOf(context).width * 0.72).clamp(
      260.0,
      300.0,
    );

    return Drawer(
      width: drawerWidth,
      elevation: 10,
      shadowColor: AppColors.cardShadow,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadiusDirectional.horizontal(
          end: Radius.circular(AppSizes.cardRadius),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _NavigationHeader(),
              const SizedBox(height: 18),
              Expanded(
                child: ListView.builder(
                  key: const ValueKey('main-shell-drawer-list'),
                  padding: EdgeInsets.zero,
                  itemCount: destinations.length,
                  itemBuilder: (context, index) {
                    final destination = destinations[index];
                    return _NavigationItem(
                      destination: destination,
                      isSelected: index == currentIndex,
                      onTap: () => onDestinationSelected(index),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  final _ShellDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavigationItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.primary : AppColors.statusNeutralText;
    final background = isSelected ? AppColors.activeBg : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isSelected ? destination.selectedIcon : destination.icon,
                  size: 22,
                  color: color,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    destination.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellNavigationRail extends StatelessWidget {
  final List<_ShellDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  const _ShellNavigationRail({
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: AppSizes.cardShadowBlur,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: NavigationRail(
          selectedIndex: currentIndex,
          onDestinationSelected: onDestinationSelected,
          minWidth: 88,
          labelType: NavigationRailLabelType.all,
          backgroundColor: AppColors.surface,
          selectedIconTheme: const IconThemeData(color: AppColors.primary),
          selectedLabelTextStyle: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
          unselectedIconTheme: const IconThemeData(
            color: AppColors.inactiveTab,
          ),
          unselectedLabelTextStyle: const TextStyle(
            color: AppColors.inactiveTab,
          ),
          leading: const Padding(
            padding: EdgeInsets.only(top: 14, bottom: 22),
            child: ChickMarkLogo(logoSize: 58, compact: true),
          ),
          destinations: destinations.map((destination) {
            return NavigationRailDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: Text(destination.label),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NavigationHeader extends StatelessWidget {
  const _NavigationHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          const Expanded(child: ChickMarkLogo(logoSize: 74)),
          IconButton(
            tooltip: context.tr('Close navigation'),
            icon: const Icon(Icons.close, color: AppColors.statusNeutralText),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
