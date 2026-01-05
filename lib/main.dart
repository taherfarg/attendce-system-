import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'presentation/pages/login/login_page.dart';
import 'presentation/pages/home/home_page.dart';
import 'presentation/pages/home/admin_home_page.dart';
import 'presentation/pages/profile/enrollment_page.dart';
import 'core/services/offline_queue.dart';
import 'core/config/app_config.dart';
import 'core/utils/time_utils.dart';
import 'core/auth/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Load environment configuration
  await AppConfig.initialize();

  // Initialize Timezones (Dubai)
  TimeUtils.initialize();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Initialize offline sync service
  final offlineQueue = OfflineQueueService();
  offlineQueue.startAutoSync();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pollux Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Slate-50
        // Color Scheme: Professional & Calm
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A), // Slate-900 (Primary)
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFF0D9488), // Teal-600 (Accent)
          tertiary: const Color(0xFF64748B), // Slate-500 (Muted)
          surface: Colors.white,
          background: const Color(0xFFF8FAFC),
          error: const Color(0xFFEF4444), // Red-500
        ),

        // Modern Typography
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme)
            .apply(
              bodyColor: const Color(0xFF1E293B), // Slate-800
              displayColor: const Color(0xFF0F172A), // Slate-900
            ),

        // Component Styles
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF0F172A)),
          titleTextStyle: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),

        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A), // Slate-900
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0F172A), width: 2),
          ),
          labelStyle: const TextStyle(color: Color(0xFF64748B)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Main auth gate that routes users based on auth state and role
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final session = snapshot.data?.session;
        if (session != null) {
          return const RoleRouter();
        } else {
          return const LoginPage();
        }
      },
    );
  }
}

/// Routes users based on role and enrollment status
class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  final _authService = AuthService();
  bool _isLoading = true;
  String? _role;
  bool _hasEnrolledFace = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      final status = await _authService.getUserStatus();
      if (mounted) {
        setState(() {
          _role = status['role'];
          _hasEnrolledFace = status['hasEnrolledFace'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString().replaceAll('AuthException: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 24),
              Text(
                'Loading...',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Colors.red.shade400,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Something went wrong',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _error = null;
                    });
                    _loadUserInfo();
                  },
                  child: const Text('Try Again'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Route based on role
    if (_role == 'admin') {
      return const AdminHomePage();
    }

    // Employee without face enrollment - go to enrollment
    if (!_hasEnrolledFace) {
      return const EnrollmentPage();
    }

    // Employee with face enrollment - go to home
    return const HomePage();
  }
}
