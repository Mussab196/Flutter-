import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_provider.dart';
import '../agent/agent_provider.dart';
import '../providers/obstacle_provider.dart';
import '../providers/fall_detection_provider.dart';
import '../providers/context_aware_provider.dart';
import '../providers/battery_automation_provider.dart';
import '../ui/responsive_utils.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool voiceEnabled = true;
  double sensitivity = 75;

  @override
  void initState() {
    super.initState();
    // Register screen with agent
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AgentProvider>(context, listen: false).updateCurrentScreen('/settings', 'Settings');
    });
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final appProvider = Provider.of<AppProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.all(Responsive.space(16)),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          isDark ? Colors.grey.shade800 : Colors.white,
                    ),
                    icon: Icon(
                      Icons.arrow_back,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(width: Responsive.space(16)),
                  Text(
                    'Settings',
                    style: GoogleFonts.poppins(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms),

            // Content
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(Responsive.space(16)),
                children: [
                  // Accessibility Section
                  _buildSectionTitle('ACCESSIBILITY'),
                  SizedBox(height: Responsive.space(12)),
                  _buildCard(
                    isDark: isDark,
                    child: Column(
                      children: [
                        _buildSwitchTile(
                          icon: Icons.volume_up_rounded,
                          title: 'Voice Feedback',
                          subtitle: 'Announce descriptions and alerts',
                          value: voiceEnabled,
                          onChanged: (v) => setState(() => voiceEnabled = v),
                        ),
                        _buildDivider(isDark),
                        Consumer<ObstacleProvider>(
                          builder: (context, obstacleProvider, child) {
                            return _buildSwitchTile(
                              icon: Icons.vibration_rounded,
                              title: 'Vibration',
                              subtitle: 'Haptic feedback for obstacle alerts',
                              value: obstacleProvider.hapticEnabled,
                              onChanged: (v) => obstacleProvider.setHapticEnabled(v),
                            );
                          },
                        ),
                        _buildDivider(isDark),
                        Consumer<AgentProvider>(
                          builder: (context, agent, child) {
                            return Column(
                              children: [
                                _buildSwitchTile(
                                  icon: Icons.smart_toy_rounded,
                                  title: 'Aura Assistant (Jarvis)',
                                  subtitle: agent.offlineMode 
                                      ? 'Offline Mode (Local commands only)'
                                      : 'Online Mode (Full AI capabilities)',
                                  value: !agent.offlineMode,
                                  onChanged: (v) => agent.toggleOfflineMode(!v),
                                ),
                              ],
                            );
                          },
                        ),
                        _buildDivider(isDark),
                        _buildSliderTile(
                          icon: Icons.tune_rounded,
                          title: 'Detection Sensitivity',
                          value: sensitivity,
                          onChanged: (v) => setState(() => sensitivity = v),
                        ),
                      ],
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 100.ms, duration: 400.ms)
                      .slideY(begin: 0.05),

                  SizedBox(height: Responsive.space(24)),

                  // Automation Section
                  _buildSectionTitle('AUTOMATION'),
                  SizedBox(height: Responsive.space(12)),
                  _buildCard(
                    isDark: isDark,
                    child: Column(
                      children: [
                        Consumer<FallDetectionProvider>(
                          builder: (context, fallProvider, child) {
                            return _buildSwitchTile(
                              icon: Icons.personal_injury_rounded,
                              title: 'Fall Detection & SOS',
                              subtitle: 'Automatically trigger SOS if a fall is detected',
                              value: fallProvider.isEnabled,
                              onChanged: (v) => fallProvider.toggleFallDetection(v),
                            );
                          },
                        ),
                        _buildDivider(isDark),
                        Consumer<ContextAwareProvider>(
                          builder: (context, contextProvider, child) {
                            return _buildSwitchTile(
                              icon: Icons.directions_walk_rounded,
                              title: 'Context Aware Modes',
                              subtitle: 'Adapt sensitivity based on your speed',
                              value: contextProvider.isEnabled,
                              onChanged: (v) => contextProvider.toggleContextAwareness(v),
                            );
                          },
                        ),
                        _buildDivider(isDark),
                        Consumer<BatteryAutomationProvider>(
                          builder: (context, batteryProvider, child) {
                            return _buildSwitchTile(
                              icon: Icons.battery_saver_rounded,
                              title: 'Smart Battery Saver',
                              subtitle: 'Automatically dim screen to save power',
                              value: batteryProvider.isEnabled,
                              onChanged: (v) => batteryProvider.toggleBatteryAutomation(v),
                            );
                          },
                        ),
                      ],
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 150.ms, duration: 400.ms)
                      .slideY(begin: 0.05),

                  SizedBox(height: Responsive.space(24)),

                  // Appearance Section
                  _buildSectionTitle('APPEARANCE'),
                  SizedBox(height: Responsive.space(12)),
                  _buildCard(
                    isDark: isDark,
                    child: _buildThemeTile(appProvider, isDark),
                  )
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 400.ms)
                      .slideY(begin: 0.05),

                  SizedBox(height: Responsive.space(24)),
                  
                  // API Configuration Section
                  _buildSectionTitle('API CONFIGURATION'),
                  SizedBox(height: Responsive.space(12)),
                  _buildCard(
                    isDark: isDark,
                    child: Consumer<AgentProvider>(
                      builder: (context, agent, child) {
                        return ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: Responsive.space(16),
                            vertical: Responsive.space(8),
                          ),
                          leading: Container(
                            width: Responsive.space(42),
                            height: Responsive.space(42),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(Responsive.radius(12)),
                            ),
                            child: Icon(
                              Icons.vpn_key_rounded,
                              color: theme.colorScheme.primary,
                              size: 20.icon,
                            ),
                          ),
                          title: Text(
                            'Configure Agent API',
                            style: GoogleFonts.poppins(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            'Select and configure AI Provider',
                            style: GoogleFonts.poppins(
                              fontSize: 11.sp,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            size: 14.icon,
                            color: theme.colorScheme.onSurface.withOpacity(0.3),
                          ),
                          onTap: () => _showApiKeyDialog(context, agent),
                        );
                      },
                    ),
                  ).animate().fadeIn(delay: 250.ms, duration: 400.ms).slideY(begin: 0.05),



                  SizedBox(height: Responsive.space(24)),

                  // Account Section
                  _buildSectionTitle('ACCOUNT'),
                  SizedBox(height: Responsive.space(12)),
                  _buildCard(
                    isDark: isDark,
                    isDestructive: true,
                    child: ListTile(
                      leading: Container(
                        width: Responsive.space(42),
                        height: Responsive.space(42),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(Responsive.radius(12)),
                        ),
                        child: Icon(
                          Icons.logout_rounded,
                          color: Colors.red,
                          size: 22.icon,
                        ),
                      ),
                      title: Text(
                        'Logout',
                        style: GoogleFonts.poppins(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Sign out of your account',
                        style: GoogleFonts.poppins(
                          fontSize: 11.sp,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 14.icon,
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                      onTap: () {
                        _showLogoutDialog(context, appProvider);
                      },
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 300.ms, duration: 400.ms)
                      .slideY(begin: 0.05),

                  SizedBox(height: Responsive.space(24)),

                  // About Section
                  _buildSectionTitle('ABOUT'),
                  SizedBox(height: Responsive.space(12)),
                  _buildCard(
                    isDark: isDark,
                    child: Column(
                      children: [
                        _buildInfoTile(
                          icon: Icons.info_outline_rounded,
                          title: 'Version',
                          value: '1.0.0',
                        ),
                        _buildDivider(isDark),
                        _buildInfoTile(
                          icon: Icons.code_rounded,
                          title: 'Build',
                          value: '2024.12.29',
                        ),
                      ],
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 400.ms, duration: 400.ms)
                      .slideY(begin: 0.05),

                  SizedBox(height: Responsive.space(32)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: Responsive.space(4)),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 11.sp,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface.withOpacity(0.5),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard(
      {required bool isDark,
      required Widget child,
      bool isDestructive = false}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900.withValues(alpha: 0.5) : Colors.white,
        borderRadius: BorderRadius.circular(Responsive.radius(20)),
        border: Border.all(
          color: isDark
              ? Colors.grey.shade800.withOpacity(0.5)
              : Colors.grey.shade200,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Responsive.radius(20)),
        child: child,
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      indent: Responsive.space(60),
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: Responsive.space(16), vertical: Responsive.space(12)),
      child: Row(
        children: [
          Container(
            width: Responsive.space(42),
            height: Responsive.space(42),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.grey.shade800
                  : theme.colorScheme.secondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(Responsive.radius(12)),
            ),
            child: Icon(
              icon,
              color: theme.colorScheme.secondary,
              size: 20.icon,
            ),
          ),
          SizedBox(width: Responsive.space(16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 11.sp,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: Responsive.isSmall ? 0.85 : 1.0,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderTile({
    required IconData icon,
    required String title,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.all(Responsive.space(16)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: Responsive.space(42),
                height: Responsive.space(42),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.shade800
                      : theme.colorScheme.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(Responsive.radius(12)),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.secondary,
                  size: 20.icon,
                ),
              ),
              SizedBox(width: Responsive.space(16)),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${value.round()}%',
                style: GoogleFonts.poppins(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          SizedBox(height: Responsive.space(12)),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: theme.colorScheme.secondary,
              inactiveTrackColor: theme.colorScheme.secondary.withOpacity(0.2),
              thumbColor: theme.colorScheme.secondary,
              overlayColor: theme.colorScheme.secondary.withOpacity(0.1),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeTile(AppProvider appProvider, bool isDark) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: Responsive.space(16), vertical: Responsive.space(12)),
      child: Row(
        children: [
          Container(
            width: Responsive.space(42),
            height: Responsive.space(42),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.grey.shade800
                  : theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(Responsive.radius(12)),
            ),
            child: Icon(
              appProvider.isDarkMode
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              color: theme.colorScheme.primary,
              size: 20.icon,
            ),
          )
              .animate(target: appProvider.isDarkMode ? 1 : 0)
              .rotate(begin: 0, end: 0.5, duration: 300.ms),
          SizedBox(width: Responsive.space(16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appProvider.isDarkMode ? 'Dark Theme' : 'Light Theme',
                  style: GoogleFonts.poppins(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  appProvider.isDarkMode
                      ? 'Easy on eyes, saves battery'
                      : 'Bright and cheerful interface',
                  style: GoogleFonts.poppins(
                    fontSize: 11.sp,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: Responsive.isSmall ? 0.85 : 1.0,
            child: Switch(
              value: appProvider.isDarkMode,
              onChanged: (_) => appProvider.toggleDarkMode(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: Responsive.space(16), vertical: Responsive.space(12)),
      child: Row(
        children: [
          Container(
            width: Responsive.space(42),
            height: Responsive.space(42),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.grey.shade800
                  : theme.colorScheme.onSurface.withOpacity(0.05),
              borderRadius: BorderRadius.circular(Responsive.radius(12)),
            ),
            child: Icon(
              icon,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              size: 20.icon,
            ),
          ),
          SizedBox(width: Responsive.space(16)),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13.sp,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AppProvider appProvider) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Logout',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: GoogleFonts.poppins(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              appProvider.logout();
              context.go('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Logout',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showApiKeyDialog(BuildContext context, AgentProvider agent) {
    final theme = Theme.of(context);
    
    // We will use a StatefulBuilder to manage local state for the dropdown
    showDialog(
      context: context,
      builder: (context) {
        bool isAzureSelected = false; // Default to Gemini
        
        final geminiKey = agent.geminiApiKey == 'YOUR_GEMINI_API_KEY_HERE' ? '' : agent.geminiApiKey;
        final azureKey = agent.azureApiKey == 'YOUR_AZURE_API_KEY_HERE' ? '' : agent.azureApiKey;
        
        final controller = TextEditingController(text: geminiKey);

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: theme.scaffoldBackgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Responsive.radius(20))),
              title: Text(
                'Configure API',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select API Provider',
                    style: GoogleFonts.poppins(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: Responsive.space(8)),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark 
                          ? Colors.grey.shade900 
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<bool>(
                        value: isAzureSelected,
                        isExpanded: true,
                        dropdownColor: theme.scaffoldBackgroundColor,
                        items: [
                          DropdownMenuItem(
                            value: false,
                            child: Text('Gemini API', style: GoogleFonts.poppins()),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: Text('Azure API', style: GoogleFonts.poppins()),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              isAzureSelected = value;
                              controller.text = isAzureSelected ? azureKey : geminiKey;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: Responsive.space(16)),
                  Text(
                    isAzureSelected ? 'Enter Azure API Key' : 'Enter Gemini API Key',
                    style: GoogleFonts.poppins(
                      fontSize: 13.sp,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  SizedBox(height: Responsive.space(8)),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    style: GoogleFonts.poppins(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Key...',
                      hintStyle: GoogleFonts.poppins(color: Colors.grey),
                      filled: true,
                      fillColor: theme.brightness == Brightness.dark 
                          ? Colors.grey.shade900 
                          : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Responsive.radius(12)),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: Responsive.space(16), 
                        vertical: Responsive.space(14)
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (isAzureSelected) {
                      agent.setAzureApiKey(controller.text.trim());
                    } else {
                      agent.setApiKey(controller.text.trim());
                    }
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('API Key saved successfully', style: GoogleFonts.poppins()),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Responsive.radius(10))),
                  ),
                  child: Text(
                    'Save',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          }
        );
      },
    );
  }
}
