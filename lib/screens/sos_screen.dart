import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';
import '../ui/responsive_utils.dart';
import '../providers/sos_provider.dart';
import '../data/models/emergency_contact_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/fall_detection_provider.dart';
import '../agent/agent_provider.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with TickerProviderStateMixin {
  bool triplePress = false;
  bool autoSend = true;
  bool _isSendingSOS = false; // Local flag to prevent multiple taps

  // TTS instance
  final FlutterTts _tts = FlutterTts();

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _rippleController;
  late AnimationController _successController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rippleAnimation;
  late Animation<double> _successAnimation;

  bool _showSuccess = false;


  @override
  void initState() {
    super.initState();

    // Pulse animation for SOS button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Ripple animation for sending state
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _rippleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );

    // Success animation
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );

    // Load contacts when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sosProvider = Provider.of<SosProvider>(context, listen: false);
      sosProvider.loadContacts();
      _loadSettings();
      
      // Register screen with agent
      Provider.of<AgentProvider>(context, listen: false).updateCurrentScreen('/sos', 'Emergency SOS');

      if (sosProvider.autoTrigger) {
        sosProvider.autoTrigger = false; // Reset it immediately
        _sendSOS();
      }
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      triplePress = prefs.getBool('sos_triple_press_enabled') ?? false;
      autoSend = prefs.getBool('sos_auto_send_enabled') ?? true;
    });
  }

  Future<void> _saveTriplePress(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sos_triple_press_enabled', value);
    setState(() => triplePress = value);
  }

  Future<void> _saveAutoSend(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sos_auto_send_enabled', value);
    setState(() => autoSend = value);
  }

  @override
  void dispose() {
    _tts.stop();
    _pulseController.dispose();
    _rippleController.dispose();
    _successController.dispose();
    super.dispose();
  }

  void _sendSOS() async {
    // Prevent multiple taps
    if (_isSendingSOS) return;

    setState(() => _isSendingSOS = true);

    final sosProvider = Provider.of<SosProvider>(context, listen: false);

    // Start sending animation (run only for 2 seconds max)
    _pulseController.repeat(reverse: true);
    _rippleController.repeat();

    final success = await sosProvider.sendSosAlert();

    // Stop sending animations immediately
    _pulseController.stop();
    _pulseController.reset();
    _rippleController.stop();
    _rippleController.reset();

    if (mounted) {
      if (success) {
        // Show success animation
        setState(() => _showSuccess = true);
        _successController.forward();

        // Speak success message
        final count = sosProvider.smsSentCount;
        await _tts.speak(
            'SOS Alert sent successfully. $count messages sent to your emergency contacts.');

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          _successController.reset();
          setState(() => _showSuccess = false);
        }
      } else {
        // Speak error message
        await _tts.speak('Failed to send SOS alert. Please try again.');
      }

      // Reset local sending flag
      setState(() => _isSendingSOS = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle_rounded : Icons.error_outline,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  success
                      ? 'SOS sent! ${sosProvider.smsSentCount} messages delivered.'
                      : sosProvider.errorMessage ?? 'Failed to send SOS',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor:
              success ? const Color(0xFF00B894) : Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _callContact(String phone) async {
    final sosProvider = Provider.of<SosProvider>(context, listen: false);
    await sosProvider.makeCall(phone);
  }

  /// Show Add/Edit Contact Dialog
  void _showAddEditContactDialog({EmergencyContactModel? existingContact}) {
    final sosProvider = Provider.of<SosProvider>(context, listen: false);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final nameController =
        TextEditingController(text: existingContact?.name ?? '');
    final phoneController =
        TextEditingController(text: existingContact?.phone ?? '');
    final roleController =
        TextEditingController(text: existingContact?.role ?? '');

    IconData selectedIcon = existingContact?.icon ?? Icons.person_rounded;
    Color selectedColor = existingContact?.color ?? const Color(0xFF4A90D9);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(Responsive.space(20)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with close button
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          existingContact != null
                              ? 'Edit Contact'
                              : 'Add Emergency Contact',
                          style: GoogleFonts.poppins(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: EdgeInsets.all(Responsive.space(6)),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color:
                                isDark ? Colors.white54 : Colors.grey.shade600,
                            size: 20.icon,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: Responsive.space(20)),

                  // Name Field
                  _buildTextField(
                    controller: nameController,
                    label: 'Name',
                    hint: 'Enter contact name',
                    icon: Icons.person_outline_rounded,
                    isDark: isDark,
                  ),
                  SizedBox(height: Responsive.space(14)),

                  // Phone Number Field
                  _buildTextField(
                    controller: phoneController,
                    label: 'Phone Number',
                    hint: '+923001234567',
                    icon: Icons.phone_outlined,
                    isDark: isDark,
                    keyboardType: TextInputType.phone,
                  ),
                  SizedBox(height: Responsive.space(14)),

                  // Role Field
                  _buildTextField(
                    controller: roleController,
                    label: 'Role',
                    hint: 'Family, Doctor, Friend, etc.',
                    icon: Icons.badge_outlined,
                    isDark: isDark,
                  ),

                  SizedBox(height: Responsive.space(7)),
                  // Action Buttons
                  Row(
                    children: [
                      // Delete Button (only for edit)
                      if (existingContact != null)
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              sosProvider
                                  .removeContact(existingContact.id ?? '');
                              Navigator.pop(context);
                              _showSnackBar('Contact deleted', isError: false);
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  vertical: Responsive.space(14)),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.red.shade600,
                                    size: 20.icon,
                                  ),
                                  SizedBox(width: Responsive.space(6)),
                                  Text(
                                    'Delete',
                                    style: GoogleFonts.poppins(
                                      color: Colors.red.shade600,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14.sp,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (existingContact != null)
                        SizedBox(width: Responsive.space(12)),

                      // Save Button
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (nameController.text.isEmpty ||
                                phoneController.text.isEmpty) {
                              _showSnackBar('Please fill name and phone number',
                                  isError: true);
                              return;
                            }

                            // Validate phone format (basic check)
                            final phoneText = phoneController.text.trim();
                            if (phoneText.length < 4) {
                              _showSnackBar('Please enter a valid phone number',
                                  isError: true);
                              return;
                            }

                            final newContact = EmergencyContactModel(
                              id: existingContact?.id ??
                                  DateTime.now()
                                      .millisecondsSinceEpoch
                                      .toString(),
                              name: nameController.text.trim(),
                              phone: phoneText,
                              role: roleController.text.trim().isEmpty
                                  ? 'Contact'
                                  : roleController.text.trim(),
                              icon: selectedIcon,
                              color: selectedColor,
                            );

                            if (existingContact != null) {
                              sosProvider.updateContact(
                                  existingContact.id ?? '', newContact);
                              _showSnackBar('Contact updated successfully',
                                  isError: false);
                            } else {
                              sosProvider.addContact(newContact);
                              _showSnackBar('Contact added successfully',
                                  isError: false);
                            }

                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                vertical: Responsive.space(14)),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFE74C3C), Color(0xFFC0392B)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFFE74C3C).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  existingContact != null
                                      ? Icons.save_rounded
                                      : Icons.add_rounded,
                                  color: Colors.white,
                                  size: 20.icon,
                                ),
                                SizedBox(width: Responsive.space(6)),
                                Text(
                                  existingContact != null ? 'Update' : 'Add',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.sp,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: Responsive.space(10)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : Colors.grey.shade700,
          ),
        ),
        SizedBox(height: Responsive.space(6)),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            ),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: GoogleFonts.poppins(
              fontSize: 14.sp,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.poppins(
                fontSize: 13.sp,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
              prefixIcon: Icon(
                icon,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
                size: 20.icon,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: Responsive.space(14),
                vertical: Responsive.space(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor:
            isError ? Colors.red.shade600 : const Color(0xFF00B894),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sosProvider = Provider.of<SosProvider>(context);
    final contacts = sosProvider.contacts;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Header
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: Responsive.space(8),
                      vertical: Responsive.space(8)),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: theme.colorScheme.onSurface,
                        ),
                        onPressed: () => context.go('/home'),
                      ),
                      Expanded(
                        child: Text(
                          "Emergency SOS",
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFE74C3C),
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.history_rounded,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                        onPressed: () {
                          sosProvider.loadSosHistory();
                          _showHistoryDialog();
                        },
                      ),
                    ],
                  ),
                ),

                // SOS Button with Animations
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                      vertical: MediaQuery.of(context).size.height * 0.03),
                  child: Center(
                    child: GestureDetector(
                      onTap: _isSendingSOS ? null : _sendSOS,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([
                          _pulseAnimation,
                          _rippleAnimation,
                        ]),
                        builder: (context, child) {
                          final btnSize = Responsive.space(
                              (MediaQuery.of(context).size.width * 0.28)
                                  .clamp(100.0, 130.0));

                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // Ripple effect circles
                              if (_isSendingSOS) ...[
                                for (int i = 0; i < 3; i++)
                                  _buildRipple(
                                    btnSize,
                                    (_rippleAnimation.value + i * 0.3) % 1.0,
                                  ),
                              ],

                              // Main SOS button
                              Transform.scale(
                                scale:
                                    _isSendingSOS ? _pulseAnimation.value : 1.0,
                                child: Container(
                                  width: btnSize,
                                  height: btnSize,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFE74C3C),
                                        Color(0xFFC0392B)
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFE74C3C)
                                            .withOpacity(
                                                _isSendingSOS ? 0.6 : 0.3),
                                        blurRadius: _isSendingSOS ? 30 : 20,
                                        spreadRadius: _isSendingSOS ? 5 : 2,
                                      )
                                    ],
                                  ),
                                  child: Center(
                                    child: _isSendingSOS
                                        ? const CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 3,
                                          )
                                        : Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.sos_rounded,
                                                color: Colors.white,
                                                size: 32.icon,
                                              ),
                                              SizedBox(
                                                  height: Responsive.space(4)),
                                              Text(
                                                "TAP",
                                                style: GoogleFonts.poppins(
                                                  fontSize: 11.sp,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white
                                                      .withOpacity(0.9),
                                                  letterSpacing: 2,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // Hold instruction
                Text(
                  'Tap to send emergency SMS to all contacts',
                  style: GoogleFonts.poppins(
                    fontSize: 12.sp,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),

                SizedBox(height: MediaQuery.of(context).size.height * 0.02),

                // Scrollable Content
                Expanded(
                  child: sosProvider.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                              horizontal: Responsive.space(20)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Emergency Contacts Section
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Emergency Contacts",
                                    style: GoogleFonts.poppins(
                                      color: theme.colorScheme.onSurface,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _showAddEditContactDialog(),
                                    child: Container(
                                      padding:
                                          EdgeInsets.all(Responsive.space(8)),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE74C3C)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(
                                            Responsive.radius(10)),
                                      ),
                                      child: Icon(
                                        Icons.add_rounded,
                                        color: const Color(0xFFE74C3C),
                                        size: 18.icon,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: Responsive.space(14)),

                              // Contact Cards
                              ...contacts.map((c) => _buildContactCard(
                                    c,
                                    isDark,
                                    () => _callContact(c.phone),
                                    () => _showAddEditContactDialog(
                                        existingContact: c),
                                  )),

                              SizedBox(height: Responsive.space(24)),

                              // Settings Section
                              Text(
                                "Quick Settings",
                                style: GoogleFonts.poppins(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: Responsive.space(14)),

                              _buildSettingCard(
                                "Triple-Press Volume",
                                "Activate SOS by pressing volume button 3 times",
                                Icons.touch_app_rounded,
                                triplePress,
                                (v) => _saveTriplePress(v),
                                isDark,
                              ),

                              _buildSettingCard(
                                "Auto-Send Location",
                                "Automatically share your GPS location",
                                Icons.location_on_rounded,
                                autoSend,
                                (v) => _saveAutoSend(v),
                                isDark,
                              ),

                              SizedBox(height: Responsive.space(30)),
                            ],
                          ),
                        ),
                ),
              ],
            ),

            // Success overlay animation
            if (_showSuccess)
              AnimatedBuilder(
                animation: _successAnimation,
                builder: (context, child) {
                  return Container(
                    color:
                        Colors.black.withOpacity(0.3 * _successAnimation.value),
                    child: Center(
                      child: Transform.scale(
                        scale: _successAnimation.value,
                        child: Container(
                          padding: EdgeInsets.all(Responsive.space(30)),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00B894),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00B894).withOpacity(0.4),
                                blurRadius: 30,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 60.icon,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // Build ripple effect circle
  Widget _buildRipple(double baseSize, double animValue) {
    return Container(
      width: baseSize + (animValue * 60),
      height: baseSize + (animValue * 60),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFE74C3C).withOpacity(1.0 - animValue),
          width: 3 * (1.0 - animValue),
        ),
      ),
    );
  }

  void _showHistoryDialog() {
    final sosProvider = Provider.of<SosProvider>(context, listen: false);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(Responsive.space(20)),
              child: Row(
                children: [
                  Text(
                    'SOS History',
                    style: GoogleFonts.poppins(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.close_rounded,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: sosProvider.sosHistory.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 48.icon,
                            color: theme.colorScheme.onSurface.withOpacity(0.3),
                          ),
                          SizedBox(height: Responsive.space(12)),
                          Text(
                            'No SOS alerts sent yet',
                            style: GoogleFonts.poppins(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.5),
                              fontSize: 14.sp,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(
                          horizontal: Responsive.space(20)),
                      itemCount: sosProvider.sosHistory.length,
                      itemBuilder: (context, index) {
                        final alert = sosProvider.sosHistory[index];
                        final timestamp = alert['createdAt']?.toDate();
                        return Container(
                          margin: EdgeInsets.only(bottom: Responsive.space(12)),
                          padding: EdgeInsets.all(Responsive.space(14)),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade900
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(Responsive.space(10)),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFFE74C3C).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.sos_rounded,
                                  color: const Color(0xFFE74C3C),
                                  size: 20.icon,
                                ),
                              ),
                              SizedBox(width: Responsive.space(12)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SOS Alert Sent',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
                                        fontSize: 13.sp,
                                      ),
                                    ),
                                    Text(
                                      timestamp != null
                                          ? '${timestamp.day}/${timestamp.month}/${timestamp.year} at ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}'
                                          : 'Unknown time',
                                      style: GoogleFonts.poppins(
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.5),
                                        fontSize: 11.sp,
                                      ),
                                    ),
                                    if (alert['recipients'] != null)
                                      Text(
                                        'To: ${(alert['recipients'] as List).join(', ')}',
                                        style: GoogleFonts.poppins(
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.5),
                                          fontSize: 10.sp,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
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
      ),
    );
  }

  Widget _buildContactCard(EmergencyContactModel contact, bool isDark,
      VoidCallback onCall, VoidCallback onEdit) {
    return GestureDetector(
      onTap: onEdit,
      child: Container(
        margin: EdgeInsets.only(bottom: Responsive.space(12)),
        padding: EdgeInsets.all(Responsive.space(14)),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade900.withOpacity(0.5) : Colors.white,
          borderRadius: BorderRadius.circular(Responsive.radius(16)),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: Responsive.space(44),
              height: Responsive.space(44),
              decoration: BoxDecoration(
                color: contact.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(Responsive.radius(14)),
              ),
              child: Icon(
                contact.icon,
                color: contact.color,
                size: 22.icon,
              ),
            ),
            SizedBox(width: Responsive.space(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contact.name,
                          style: GoogleFonts.poppins(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 14.sp,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.edit_outlined,
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                        size: 14.icon,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: Responsive.space(8),
                            vertical: Responsive.space(2)),
                        decoration: BoxDecoration(
                          color: contact.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          contact.role,
                          style: GoogleFonts.poppins(
                            color: contact.color,
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(width: Responsive.space(8)),
                      Expanded(
                        child: Text(
                          contact.phone,
                          style: GoogleFonts.poppins(
                            color:
                                isDark ? Colors.white54 : Colors.grey.shade600,
                            fontSize: 10.sp,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onCall,
              child: Container(
                width: Responsive.space(38),
                height: Responsive.space(38),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B894).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(Responsive.radius(12)),
                ),
                child: Icon(
                  Icons.call_rounded,
                  color: const Color(0xFF00B894),
                  size: 18.icon,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingCard(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    Function(bool) onChanged,
    bool isDark,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: Responsive.space(12)),
      padding: EdgeInsets.all(Responsive.space(14)),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900.withOpacity(0.5) : Colors.white,
        borderRadius: BorderRadius.circular(Responsive.radius(16)),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: Responsive.space(42),
            height: Responsive.space(42),
            decoration: BoxDecoration(
              color: const Color(0xFFE74C3C).withOpacity(0.1),
              borderRadius: BorderRadius.circular(Responsive.radius(12)),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFE74C3C),
              size: 20.icon,
            ),
          ),
          SizedBox(width: Responsive.space(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.sp,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                    fontSize: 10.sp,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: Responsive.isSmall ? 0.8 : 0.9,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFFE74C3C),
              activeTrackColor: const Color(0xFFE74C3C).withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }
}
