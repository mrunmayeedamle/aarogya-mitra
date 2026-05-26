import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/intro_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  final prefs = await SharedPreferences.getInstance();
  final seenIntro = prefs.getBool('seenIntro') ?? false;

  runApp(MyApp(showIntro: !seenIntro));
}

class MyApp extends StatelessWidget {
  final bool showIntro;

  const MyApp({super.key, required this.showIntro});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, ChatProvider>(
          create: (_) => ChatProvider(),
          update: (_, auth, chat) {
            chat!.setUserEmail(auth.userEmail);
            return chat;
          },
        ),
      ],
      child: MaterialApp(
        title: 'AarogyaMitra',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: showIntro ? const IntroScreen() : const AuthWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return authProvider.isAuthenticated ? HomeScreen() : const LoginScreen();
  }
}
