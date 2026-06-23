import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_provider.dart';
import '../providers/auth_provider.dart';
import '../ui/responsive_utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  late AnimationController _bgController;

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
    _emailController.dispose();
    _passwordController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_formKey.currentState?.validate() ?? false) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final appProvider = Provider.of<AppProvider>(context, listen: false);

      setState(() => _isLoading = true);

      // Use Firebase login (change to loginDemo() if Firebase not configured)
      final success = await authProvider.loginWithFirebase(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      setState(() => _isLoading = false);

      if (success) {
        appProvider.setAuthenticated(true);
        if (mounted) context.go('/home');
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
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
            top: -size.width * 0.3,
            right: -size.width * 0.2,
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _bgController.value * 2 * 3.14159,
                  child: Container(
                    width: size.width * 0.7,
                    height: size.width * 0.7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF4A90D9).withOpacity(0.15),
                          const Color(0xFF4A90D9).withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: -size.width * 0.4,
            left: -size.width * 0.3,
            child: Container(
              width: size.width * 0.8,
              height: size.width * 0.8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6C5CE7).withOpacity(0.1),
                    const Color(0xFF6C5CE7).withOpacity(0.0),
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
                  vertical: Responsive.space(16)),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: size.height * 0.03),

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

                    SizedBox(height: size.height * 0.025),

                    // Title with gradient effect
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF4A90D9), Color(0xFF6C5CE7)],
                      ).createShader(bounds),
                      child: Text(
                        'Welcome Back',
                        style: GoogleFonts.poppins(
                          fontSize: 28.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.2),

                    SizedBox(height: Responsive.space(8)),

                    Text(
                      'Login to access Aura',
                      style: GoogleFonts.poppins(
                        fontSize: 13.sp,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ).animate().fadeIn(delay: 200.ms),

                    SizedBox(height: size.height * 0.03),

                    // Email Field
                    _buildLabel('Email Address', isDark),
                    SizedBox(height: Responsive.space(10)),
                    _buildTextField(
                      controller: _emailController,
                      hintText: 'your@email.com',
                      prefixIcon: Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress,
                      isDark: isDark,
                    ).animate().fadeIn(delay: 250.ms).slideX(begin: -0.05),

                    SizedBox(height: Responsive.space(20)),

                    // Password Field
                    _buildLabel('Password', isDark),
                    SizedBox(height: Responsive.space(10)),
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
                    ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.05),

                    SizedBox(height: Responsive.space(16)),

                    // Remember me and Forgot password
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Transform.scale(
                              scale: Responsive.isSmall ? 0.95 : 1.1,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (value) {
                                  setState(() => _rememberMe = value ?? false);
                                },
                                activeColor: const Color(0xFF4A90D9),
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
                            Text(
                              'Remember me',
                              style: GoogleFonts.poppins(
                                fontSize: 12.sp,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => context.go('/reset-password'),
                          child: Text(
                            'Forgot Password?',
                            style: GoogleFonts.poppins(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF4A90D9),
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 350.ms),

                    SizedBox(height: Responsive.space(28)),

                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      height: Responsive.space(52),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4A90D9),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: const Color(0xFF4A90D9).withOpacity(0.5),
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
                                    'Login',
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
                        .fadeIn(delay: 400.ms)
                        .slideY(begin: 0.1)
                        .then()
                        .shimmer(delay: 500.ms, duration: 1500.ms),

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
                            'Or continue with',
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
                    ).animate().fadeIn(delay: 450.ms),

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
                              context.push('/face-login');
                            },
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),

                    SizedBox(height: size.height * 0.025),

                    // Sign up link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: GoogleFonts.poppins(
                            fontSize: 13.sp,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.go('/signup'),
                          child: Text(
                            'Sign Up',
                            style: GoogleFonts.poppins(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF4A90D9),
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 550.ms),

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

  Widget _buildLabel(String text, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF4A90D9),
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
              color: const Color(0xFF4A90D9),
              size: 20.icon,
            ),
          ),
          prefixIconConstraints: BoxConstraints(minWidth: Responsive.space(48)),
          suffixIcon: isPassword
              ? IconButton(
                  onPressed: onTogglePassword,
                  icon: Icon(
                    showPassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                    size: 20.icon,
                  ),
                )
              : null,
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
