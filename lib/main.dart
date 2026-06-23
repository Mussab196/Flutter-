import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'providers/app_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/sos_provider.dart';
import 'providers/ocr_provider.dart';
import 'providers/live_vision_provider.dart';
import 'providers/face_provider.dart';
import 'agent/action_router.dart';
import 'providers/obstacle_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/fall_detection_provider.dart';
import 'providers/context_aware_provider.dart';     
import 'providers/battery_automation_provider.dart';
import 'agent/agent_provider.dart';
import 'widgets/agent_overlay_wrapper.dart';
import 'screens/splash_screen.dart';
import 'screens/vision_chat_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/live_vision_screen.dart';
import 'screens/ocr_reader_screen.dart';
import 'screens/face_recognition_screen.dart';
import 'screens/add_face_screen.dart';        
import 'screens/navigation_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/face_auth_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (check if already initialized)
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(prefs: prefs));
}

// Custom page transition
class FadeSlideTransition extends CustomTransitionPage<void> {
  FadeSlideTransition({required super.child, super.key})
      : super(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curvedAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.03, 0),
                  end: Offset.zero,
                ).animate(curvedAnimation),
                child: child,
              ),
            );
          },
        );
}

class MyApp extends StatefulWidget {
  final SharedPreferences prefs;

  const MyApp({super.key, required this.prefs});

  // App Colors - Consistent across the app
  static const Color primaryBlue = Color(0xFF4A90D9);
  static const Color primaryCyan = Color(0xFF00BCD4);
  static const Color darkBg = Color(0xFF0D0D0D);
  static const Color darkCard = Color(0xFF1A1A1A);
  static const Color darkSurface = Color(0xFF252525);
  static const Color lightBg = Color(0xFFF5F7FA);
  static const Color lightCard = Color(0xFFFFFFFF);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // Create router ONCE — not inside build() which would reset navigation on every rebuild
    _router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/splash',
      routes: [
        GoRoute(
          path: '/splash',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const SplashScreen(),
          ),
        ),
        GoRoute(
          path: '/onboarding',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const OnboardingScreen(),
          ),
        ),
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const LoginScreen(),
          ),
        ),
        GoRoute(
          path: '/signup',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const SignupScreen(),
          ),
        ),
        GoRoute(
          path: '/reset-password',
          pageBuilder: (context, state) {
            final oobCode = state.uri.queryParameters['oobCode'];
            return FadeSlideTransition(
              key: state.pageKey,
              child: ResetPasswordScreen(oobCode: oobCode),
            );
          },
        ),
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const HomeScreen(),
          ),
        ),
        GoRoute(
          path: '/live-vision',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const LiveVisionScreen(),
          ),
        ),
        GoRoute(
          path: '/ocr-reader',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const OcrReaderScreen(),
          ),
        ),
        GoRoute(
          path: '/face-recognition',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const FaceRecognitionScreen(),
          ),
        ),
        GoRoute(
          path: '/add-face',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const AddFaceScreen(),
          ),
        ),
        GoRoute(
          path: '/navigation',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const NavigationScreen(),
          ),
        ),
        GoRoute(
          path: '/sos',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const SosScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const SettingsScreen(),
          ),
        ),
        GoRoute(
          path: '/face-login',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const FaceAuthScreen(isLogin: true),
          ),
        ),
        GoRoute(
          path: '/face-signup',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const FaceAuthScreen(isLogin: false),
          ),
        ),
        GoRoute(
          path: '/vision-chat',
          pageBuilder: (context, state) => FadeSlideTransition(
            key: state.pageKey,
            child: const VisionChatScreen(),
          ),
        ),
      ],
    );


  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider(widget.prefs)),
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ChangeNotifierProvider(create: (_) => SosProvider()),
        ChangeNotifierProvider(create: (_) => OcrProvider()..initTts()),
        ChangeNotifierProvider(create: (_) => LiveVisionProvider()),
        ChangeNotifierProvider(create: (_) => FaceProvider()),
        ChangeNotifierProvider(create: (_) => ObstacleProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(create: (_) => AgentProvider()),
        ChangeNotifierProvider(create: (_) => FallDetectionProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => ContextAwareProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => BatteryAutomationProvider()..initialize()),
      ],
      child: Consumer<AppProvider>(
        builder: (context, appProvider, child) {
          // Text theme with Poppins
          final textTheme = GoogleFonts.poppinsTextTheme();

          return MaterialApp.router(
            routerConfig: _router,
            title: 'Aura',
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              return AgentOverlayWrapper(child: child!);
            },

            // Light Theme
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              colorScheme: ColorScheme.light(
                primary: MyApp.primaryBlue,
                secondary: MyApp.primaryCyan,
                surface: MyApp.lightCard,
                onSurface: const Color(0xFF1A1A2E),
                outline: const Color(0xFFE0E0E0),
                error: const Color(0xFFE53935),
              ),
              textTheme: textTheme.apply(
                bodyColor: const Color(0xFF1A1A2E),
                displayColor: const Color(0xFF1A1A2E),
              ),
              scaffoldBackgroundColor: MyApp.lightBg,
              cardColor: MyApp.lightCard,
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                elevation: 0,
                systemOverlayStyle: SystemUiOverlayStyle.dark,
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyApp.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: MyApp.primaryBlue, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              switchTheme: SwitchThemeData(
                thumbColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return MyApp.primaryCyan;
                  }
                  return Colors.grey.shade400;
                }),
                trackColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return MyApp.primaryCyan.withValues(alpha: 0.3);
                  }
                  return Colors.grey.shade300;
                }),
              ),
              dialogTheme: DialogThemeData(
                backgroundColor: MyApp.lightCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),

            // Dark Theme
            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorScheme: ColorScheme.dark(
                primary: MyApp.primaryBlue,
                secondary: MyApp.primaryCyan,
                surface: MyApp.darkCard,
                onSurface: Colors.white,
                outline: const Color(0xFF3A3A3A),
                error: const Color(0xFFEF5350),
              ),
              textTheme: textTheme.apply(
                bodyColor: Colors.white,
                displayColor: Colors.white,
              ),
              scaffoldBackgroundColor: MyApp.darkBg,
              cardColor: MyApp.darkCard,
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                elevation: 0,
                systemOverlayStyle: SystemUiOverlayStyle.light,
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyApp.primaryCyan,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: MyApp.darkSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF3A3A3A)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF3A3A3A)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: MyApp.primaryCyan, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              switchTheme: SwitchThemeData(
                thumbColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return MyApp.primaryCyan;
                  }
                  return Colors.grey.shade600;
                }),
                trackColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return MyApp.primaryCyan.withValues(alpha: 0.3);
                  }
                  return Colors.grey.shade800;
                }),
              ),
              dialogTheme: DialogThemeData(
                backgroundColor: MyApp.darkCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),

            themeMode:
                appProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          );
        },
      ),
    );
  }
}

