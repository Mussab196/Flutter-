import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/app_provider.dart';
import '../providers/auth_provider.dart';
import '../ui/responsive_utils.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _agreeToTerms = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  late AnimationController _bgController;

  // Password strength indicators
  bool get _hasMinLength => _passwordController.text.length >= 8;
  bool get _hasUpperCase => RegExp(r'[A-Z]').hasMatch(_passwordController.text);
  bool get _hasLowerCase => RegExp(r'[a-z]').hasMatch(_passwordController.text);
  bool get _hasNumber => RegExp(r'[0-9]').hasMatch(_passwordController.text);
  bool get _passwordsMatch =>
      _passwordController.text == _confirmPasswordController.text &&
      _confirmPasswordController.text.isNotEmpty;

  int get _passwordStrength {
    int strength = 0;
    if (_hasMinLength) strength++;
    if (_hasUpperCase) strength++;
    if (_hasLowerCase) strength++;
    if (_hasNumber) strength++;
    return strength;
  }

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  bool _validateGmail(String email) {
    final gmailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@gmail\.com$', caseSensitive: false);
    return gmailRegex.hasMatch(email.trim());
  }

  bool get _isFormValid {
    return _nameController.text.trim().isNotEmpty &&
        _validateGmail(_emailController.text.trim()) &&
        _passwordStrength >= 4 &&
        _passwordsMatch &&
        _agreeToTerms;
  }

  void _handleSignup() async {
    if (_formKey.currentState!.validate() && _isFormValid) {
      setState(() => _isLoading = true);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final email = _emailController.text.trim();

      // Check if email already exists
      final emailExists = await authProvider.checkEmailExists(email);
      if (emailExists) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'This email is already registered. Please login or use another email.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Use Firebase registration (change to registerDemo() if Firebase not configured)
      final success = await authProvider.registerWithFirebase(
        name: _nameController.text.trim(),
        email: email,
        password: _passwordController.text,
      );

      setState(() => _isLoading = false);

      if (success) {
        // Show success message and go to login page
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Account created successfully! Please login.',
                      style: GoogleFonts.poppins(),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
          // Logout and go to login page
          await authProvider.logoutFirebase();
          context.go('/login');
        }
      } else {
        // Show error with proper message
        if (mounted) {
          String errorMsg = _getReadableErrorMessage(authProvider.errorMessage);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      errorMsg,
                      style: GoogleFonts.poppins(),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    }
  }

  String _getReadableErrorMessage(String? error) {
    if (error == null) return 'Something went wrong. Please try again.';

    // FirebaseAuthService already formats the errors, but it wraps them in Exception()
    if (error.startsWith('Exception: ')) {
      return error.substring(11).trim();
    }
    
    return error;
  }

  void _handleGoogleSignIn() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final appProvider = Provider.of<AppProvider>(context, listen: false);

    setState(() => _isGoogleLoading = true);

    final success = await authProvider.signInWithGoogle();

    setState(() => _isGoogleLoading = false);

    if (success) {
      appProvider.setAuthenticated(true);
      if (mounted) context.go('/home');
    } else {
      if (mounted &&
          authProvider.errorMessage != null &&
          authProvider.errorMessage != 'Google Sign-In cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getReadableErrorMessage(authProvider.errorMessage),
                    style: GoogleFonts.poppins(),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF5F7FA),
      body: Stack(
        children: [
          // Animated Background Circles
          Positioned(
            top: -size.width * 0.4,
            left: -size.width * 0.2,
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _bgController.value * 2 * 3.14159,
                  child: Container(
                    width: size.width * 0.8,
                    height: size.width * 0.8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF6C5CE7).withOpacity(0.15),
                          const Color(0xFF6C5CE7).withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: -size.width * 0.3,
            right: -size.width * 0.2,
            child: Container(
              width: size.width * 0.7,
              height: size.width * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00B894).withOpacity(0.12),
                    const Color(0xFF00B894).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: Responsive.space(24),
                  vertical: Responsive.space(12)),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: size.height * 0.015),

                    // Logo with Glow
                    Container(
                      width: Responsive.space(80),
                      height: Responsive.space(80),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF4A90D9), Color(0xFF6C5CE7)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4A90D9).withOpacity(0.4),
                            blurRadius: 25,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.remove_red_eye_rounded,
                        color: Colors.white,
                        size: 36.icon,
                      ),
                    ).animate().fadeIn(duration: 500.ms).scale(
                        begin: const Offset(0.5, 0.5),
                        curve: Curves.elasticOut),

                    SizedBox(height: size.height * 0.02),

                    // Title with gradient effect
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF6C5CE7), Color(0xFF00B894)],
                      ).createShader(bounds),
                      child: Text(
                        'Create Account',
                        style: GoogleFonts.poppins(
                          fontSize: 26.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.2),

                    SizedBox(height: Responsive.space(6)),

                    Text(
                      'Join Aura today',
                      style: GoogleFonts.poppins(
                        fontSize: 13.sp,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ).animate().fadeIn(delay: 200.ms),

                    SizedBox(height: size.height * 0.02),

                    // Full Name Field
                    _buildLabel('Full Name', isDark),
                    SizedBox(height: Responsive.space(8)),
                    _buildTextField(
                      controller: _nameController,
                      hintText: 'Your Name',
                      prefixIcon: Icons.person_rounded,
                      isDark: isDark,
                    ).animate().fadeIn(delay: 250.ms).slideX(begin: -0.05),

                    SizedBox(height: Responsive.space(14)),

                    // Email Field
                    _buildLabel('Gmail Address', isDark),
                    SizedBox(height: Responsive.space(8)),
                    _buildTextField(
                      controller: _emailController,
                      hintText: 'your.email@gmail.com',
                      prefixIcon: Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress,
                      isDark: isDark,
                      onChanged: (value) => setState(() {}),
                    ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.05),

                    // Gmail validation message
                    if (_emailController.text.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: Responsive.space(8)),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Icon(
                                _validateGmail(_emailController.text)
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                size: 16,
                                color: _validateGmail(_emailController.text)
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              SizedBox(width: Responsive.space(6)),
                              Text(
                                _validateGmail(_emailController.text)
                                    ? 'Valid Gmail address'
                                    : 'Enter valid Gmail (name@gmail.com)',
                                style: GoogleFonts.poppins(
                                  fontSize: 12.sp,
                                  color: _validateGmail(_emailController.text)
                                      ? Colors.green
                                      : Colors.red,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    SizedBox(height: Responsive.space(14)),

                    // Password Field
                    _buildLabel('Password', isDark),
                    SizedBox(height: Responsive.space(8)),
                    _buildTextField(
                      controller: _passwordController,
                      hintText: '••••••••',
                      prefixIcon: Icons.lock_rounded,
                      isPassword: true,
                      showPassword: _showPassword,
                      onTogglePassword: () {
                        setState(() => _showPassword = !_showPassword);
                      },
                      isDark: isDark,
                    ).animate().fadeIn(delay: 350.ms).slideX(begin: -0.05),

                    // Password Strength Indicator
                    if (_passwordController.text.isNotEmpty) ...[
                      SizedBox(height: Responsive.space(12)),
                      _buildPasswordStrength(isDark),
                    ],

                    SizedBox(height: Responsive.space(14)),

                    // Confirm Password Field
                    _buildLabel('Confirm Password', isDark),
                    SizedBox(height: Responsive.space(8)),
                    _buildTextField(
                      controller: _confirmPasswordController,
                      hintText: '••••••••',
                      prefixIcon: Icons.lock_rounded,
                      isPassword: true,
                      showPassword: _showConfirmPassword,
                      onTogglePassword: () {
                        setState(
                            () => _showConfirmPassword = !_showConfirmPassword);
                      },
                      isDark: isDark,
                      suffixWidget: _confirmPasswordController.text.isNotEmpty
                          ? Icon(
                              _passwordsMatch
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              color: _passwordsMatch
                                  ? const Color(0xFF00B894)
                                  : Colors.red,
                              size: 20.icon,
                            )
                          : null,
                    ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.05),

                    SizedBox(height: Responsive.space(16)),

                    // Terms Agreement
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Transform.scale(
                          scale: Responsive.isSmall ? 0.95 : 1.1,
                          child: Checkbox(
                            value: _agreeToTerms,
                            onChanged: (value) {
                              setState(() => _agreeToTerms = value ?? false);
                            },
                            activeColor: const Color(0xFF6C5CE7),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade400,
                              width: 1.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: Responsive.space(12)),
                            child: RichText(
                              text: TextSpan(
                                style: GoogleFonts.poppins(
                                  fontSize: 12.sp,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                ),
                                children: [
                                  const TextSpan(text: 'I agree to the '),
                                  TextSpan(
                                    text: 'Terms & Conditions',
                                    style: const TextStyle(
                                      color: Color(0xFF6C5CE7),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const TextSpan(text: ' and '),
                                  TextSpan(
                                    text: 'Privacy Policy',
                                    style: const TextStyle(
                                      color: Color(0xFF6C5CE7),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 450.ms),

                    SizedBox(height: Responsive.space(20)),

                    // Create Account Button
                    SizedBox(
                      width: double.infinity,
                      height: Responsive.space(50),
                      child: ElevatedButton(
                        onPressed:
                            _isFormValid && !_isLoading ? _handleSignup : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C5CE7),
                          disabledBackgroundColor:
                              const Color(0xFF6C5CE7).withOpacity(0.4),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: const Color(0xFF6C5CE7).withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(Responsive.radius(16)),
                          ),
                        ),
                        child: _isLoading
                            ? SizedBox(
                                width: 22.icon,
                                height: 22.icon,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Create Account',
                                    style: GoogleFonts.poppins(
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(width: Responsive.space(8)),
                                  Icon(Icons.arrow_forward_rounded,
                                      size: 18.icon),
                                ],
                              ),
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 500.ms)
                        .slideY(begin: 0.1)
                        .then()
                        .shimmer(delay: 500.ms, duration: 1000.ms),

                    SizedBox(height: Responsive.space(24)),

                    // Divider with text
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 1,
                            color: theme.colorScheme.onSurface.withOpacity(0.1),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: Responsive.space(16)),
                          child: Text(
                            'Or sign up with',
                            style: GoogleFonts.poppins(
                              fontSize: 11.sp,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: theme.colorScheme.onSurface.withOpacity(0.1),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 550.ms),

                    SizedBox(height: Responsive.space(18)),

                    // Social Buttons
                    Row(
                      children: [
                        Expanded(
                          child: _buildSocialButton(
                            'Google',
                            Icons.g_mobiledata_rounded,
                            const Color(0xFFEA4335),
                            isDark,
                            isLoading: _isGoogleLoading,
                            onTap: _handleGoogleSignIn,
                          ),
                        ),
                        SizedBox(width: Responsive.space(14)),
                        Expanded(
                          child: _buildSocialButton(
                            'Face ID',
                            Icons.face_retouching_natural_rounded,
                            const Color(0xFF9B59B6),
                            isDark,
                            onTap: () {
                              context.push('/face-signup');
                            },
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.1),

                    SizedBox(height: Responsive.space(24)),

                    // Login link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: GoogleFonts.poppins(
                            fontSize: 13.sp,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          child: Text(
                            'Sign In',
                            style: GoogleFonts.poppins(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF6C5CE7),
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 650.ms),

                    SizedBox(height: Responsive.space(24)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordStrength(bool isDark) {
    Color strengthColor;
    String strengthText;

    switch (_passwordStrength) {
      case 0:
      case 1:
        strengthColor = Colors.red;
        strengthText = 'Weak';
        break;
      case 2:
        strengthColor = Colors.orange;
        strengthText = 'Fair';
        break;
      case 3:
        strengthColor = Colors.yellow.shade700;
        strengthText = 'Good';
        break;
      case 4:
        strengthColor = const Color(0xFF00B894);
        strengthText = 'Strong';
        break;
      default:
        strengthColor = Colors.grey;
        strengthText = '';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: List.generate(4, (index) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                          right: index < 3 ? Responsive.space(6) : 0),
                      decoration: BoxDecoration(
                        color: index < _passwordStrength
                            ? strengthColor
                            : (isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            SizedBox(width: Responsive.space(12)),
            Text(
              strengthText,
              style: GoogleFonts.poppins(
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                color: strengthColor,
              ),
            ),
          ],
        ),
        SizedBox(height: Responsive.space(8)),
        Wrap(
          spacing: Responsive.space(12),
          runSpacing: Responsive.space(6),
          children: [
            _buildRequirement('8+ chars', _hasMinLength),
            _buildRequirement('Uppercase', _hasUpperCase),
            _buildRequirement('Lowercase', _hasLowerCase),
            _buildRequirement('Number', _hasNumber),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildRequirement(String text, bool met) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 12.icon,
          color: met ? const Color(0xFF00B894) : Colors.grey,
        ),
        SizedBox(width: Responsive.space(4)),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 10.sp,
            color: met ? const Color(0xFF00B894) : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF6C5CE7),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    required bool isDark,
    bool isPassword = false,
    bool showPassword = false,
    VoidCallback? onTogglePassword,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixWidget,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900.withOpacity(0.5) : Colors.white,
        borderRadius: BorderRadius.circular(Responsive.radius(16)),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !showPassword,
        keyboardType: keyboardType,
        onChanged: onChanged ?? (_) => setState(() {}),
        style: GoogleFonts.poppins(
          fontSize: 14.sp,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.poppins(
            fontSize: 14.sp,
            color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
          ),
          prefixIcon: Container(
            margin: EdgeInsets.only(
                left: Responsive.space(12), right: Responsive.space(8)),
            child: Icon(
              prefixIcon,
              color: const Color(0xFF6C5CE7),
              size: 20.icon,
            ),
          ),
          prefixIconConstraints: BoxConstraints(minWidth: Responsive.space(48)),
          suffixIcon: isPassword
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (suffixWidget != null) suffixWidget,
                    IconButton(
                      onPressed: onTogglePassword,
                      icon: Icon(
                        showPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade400,
                        size: 20.icon,
                      ),
                    ),
                  ],
                )
              : suffixWidget,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: Responsive.space(16),
            vertical: Responsive.space(14),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton(
      String label, IconData icon, Color color, bool isDark,
      {VoidCallback? onTap, bool isLoading = false}) {
    return Container(
      height: Responsive.space(50),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900.withOpacity(0.5) : Colors.white,
        borderRadius: BorderRadius.circular(Responsive.radius(16)),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(Responsive.radius(16)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 20.icon,
                  height: 20.icon,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, color: color, size: 24.icon),
              SizedBox(width: Responsive.space(10)),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
