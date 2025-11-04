import 'package:flutter/material.dart';
import 'package:frontend/screens/intro/introduction_animation_screen.dart';
// replaced registration import with the OTP sign-in page
import 'package:frontend/screens/signin_otp_page.dart';
import 'package:frontend/screens/home_page.dart';
import 'package:frontend/utils/user_prefs.dart';
import 'package:frontend/screens/reset_pin_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserPrefs.init();
  runApp(const SafetyMitraApp());
}

class SafetyMitraApp extends StatelessWidget {
  const SafetyMitraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final initial = UserPrefs.isLoggedIn ? '/home' : '/intro';

    return MaterialApp(
      title: 'Safety Mitra',
      debugShowCheckedModeBanner: false,
      initialRoute: initial,
      routes: {
        '/intro': (_) => const IntroductionAnimationScreen(),
        // use the new SignInOtpPage for auth
        '/auth': (_) => const SignInOtpPage(),
        '/home': (_) => const HomeScreen(),
        '/reset-pin': (_) => const ResetPinPage(),
      },
      onGenerateRoute: (settings) => null,
    );
  }
}
