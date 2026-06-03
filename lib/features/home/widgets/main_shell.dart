import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/debug/startup_timer.dart';
import '../../../core/navigation/shell_navigation_scope.dart';
import '../../../providers/customers_provider.dart';
import '../../../services/sync/bg_sync_service.dart';
import '../../../widgets/chick_mark_logo.dart';
import '../../auth/providers/auth_provider.dart';
import '../../home/screens/home_screen.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../customers/screens/customers_screen.dart';
import '../../audits/screens/audits_screen.dart';
import '../../bmk/screens/bmk_screen.dart';
import '../../settings/screens/settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentIndex = 0;
  final List<int> _tabHistory = [];
  bool _syncTriggered = false;

  static const List<_ShellDestination> _destinations = [
    _ShellDestination(
      label: AppStrings.homeTab,
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    _ShellDestination(
      label: AppStrings.dashboardTab,
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
    ),
    _ShellDestination(
      label: AppStrings.customersTab,
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
    ),
    _ShellDestination(
      label: AppStrings.auditsTab,
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
    ),
    _ShellDestination(
      label: AppStrings.bmkTab,
      icon: Icons.science_outlined,
      selectedIcon: Icons.science,
    ),
    _ShellDestination(
      label: AppStrings.settingsTab,
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  final Map<int, Widget> _builtScreens = {};
  bool _homeLoaded = false;

  @override
  void initState() {
    super.initState();
    StartupTimer.lap('main_shell_init');
  }

  void _triggerBackgroundSync() {
    if (_syncTriggered) return;
    _syncTriggered = true;
    StartupTimer.lap('bg_sync_triggering');
    final authProvider = context.read<AuthProvider>();
    final customersProvider = context.read<CustomersProvider>();
    final bgSync = BgSyncService();
    bgSync.runBackgroundSync(
      authProvider: authProvider,
      customersProvider: customersProvider,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_homeLoaded) {
      _builtScreens[0] = _buildScreen(0);
      _homeLoaded = true;
      StartupTimer.lap('home_screen_built');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerBackgroundSync();
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

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const DashboardScreen();
      case 2:
        return const CustomersScreen();
      case 3:
        return const AuditsScreen();
      case 4:
        return const BmkScreen();
      case 5:
        return const SettingsScreen();
      default:
        return const HomeScreen();
    }
  }

  void _selectDestination(int index) {
    if (_currentIndex != index) {
      if (!_builtScreens.containsKey(index)) {
        final tabNames = [
          'home',
          'dashboard',
          'customers',
          'audits',
          'bmk',
          'settings',
        ];
        _builtScreens[index] = _buildScreen(index);
        StartupTimer.lap('${tabNames[index]}_tab_first_load');
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
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  const _ShellNavigationDrawer({
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
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(AppSizes.cardRadius),
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
              ...List.generate(_MainShellState._destinations.length, (index) {
                final destination = _MainShellState._destinations[index];
                return _NavigationItem(
                  destination: destination,
                  isSelected: index == currentIndex,
                  onTap: () => onDestinationSelected(index),
                );
              }),
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
    final color = isSelected ? AppColors.primary : const Color(0xFF535966);
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
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  const _ShellNavigationRail({
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
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
          backgroundColor: Colors.white,
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
          destinations: _MainShellState._destinations.map((destination) {
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
            tooltip: 'Close navigation',
            icon: const Icon(Icons.close, color: Color(0xFF535966)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
