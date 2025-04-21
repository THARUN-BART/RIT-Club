import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rit_club/Authentication/signup.dart';
import 'package:rit_club/pages/Admin/admin_home.dart';
import 'package:rit_club/pages/User/Home.dart';
import 'package:rit_club/widgets/gradient_button.dart';
import 'package:google_fonts/google_fonts.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  bool _obsecureText = true;
  bool _isLoading = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _forgotPasswordEmailController =
      TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _forgotPasswordEmailController.dispose();
    super.dispose();
  }

  void _showMessage(String title, String message) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
    );
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage("Error", "Please enter both email and password");
      return;
    }

    try {
      setState(() => _isLoading = true);

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = credential.user?.uid;
      if (uid == null) {
        throw Exception("User ID not found");
      }

      // Fetch role from Firestore
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!userDoc.exists || !userDoc.data()!.containsKey('role')) {
        _showMessage("Error", "User role not defined. Contact admin.");
        return;
      }

      final role = userDoc['role'];

      if (role == 'USER') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomePage()), // 👤 User's Home Page
        );
      } else if (role == 'ADMIN') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => AdminHome()),
        );
      } else {
        _showMessage("Error", "Unknown role assigned to user.");
      }
    } on FirebaseAuthException catch (e) {
      String message = "Login failed. Please try again.";

      if (e.code == 'user-not-found') {
        message = "No user found with this email.";
      } else if (e.code == 'wrong-password') {
        message = "Wrong password. Please try again.";
      } else if (e.code == 'user-disabled') {
        message = "This account has been disabled.";
      }

      _showMessage("Login Error", message);
    } catch (e) {
      _showMessage("Error", "An unexpected error occurred. Please try again.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    _forgotPasswordEmailController.text =
        _emailController.text; // Pre-fill with login email if available

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Reset Password"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Enter your email address and we'll send you a link to reset your password.",
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _forgotPasswordEmailController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: "Email",
                    hintText: 'Enter your email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CANCEL"),
              ),
              TextButton(
                onPressed: () {
                  _verifyEmailAndSendReset();
                  Navigator.pop(context);
                },
                child: const Text("SEND RESET LINK"),
              ),
            ],
          ),
    );
  }

  Future<void> _verifyEmailAndSendReset() async {
    final email = _forgotPasswordEmailController.text.trim();

    if (email.isEmpty) {
      _showMessage("Error", "Please enter your email");
      return;
    }

    try {
      setState(() => _isLoading = true);

      // Check if the email exists by querying Firestore
      // This assumes you have a 'users' collection with documents that have an 'email' field
      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();

      if (querySnapshot.docs.isEmpty) {
        _showMessage(
          "Email Not Found",
          "This email is not registered in our system. Please check the email or sign up.",
        );
        setState(() => _isLoading = false);
        return;
      }

      // If we reach here, the email exists in the database
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      _showMessage(
        "Reset Link Sent",
        "Check your inbox for instructions to reset your password.",
      );
    } on FirebaseAuthException catch (e) {
      String message = "Failed to send reset link. Please try again.";

      if (e.code == 'user-not-found') {
        message = "No user found with this email.";
      } else if (e.code == 'invalid-email') {
        message = "Invalid email address.";
      }

      _showMessage("Error", message);
    } catch (e) {
      _showMessage("Error", "An unexpected error occurred. Please try again.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true, // Ensures the app bar stays at the top
            expandedHeight: 200.0, // Height of the app bar when expanded
            backgroundColor: Colors.black, // App bar turns black when collapsed
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                "LOGIN",
                style: GoogleFonts.salsa(fontSize: 32, color: Colors.white),
              ),
              centerTitle: true,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0347F4), Colors.blue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 50),
                  const Text(
                    'Welcome Back! Please login to continue.',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: "Email",
                        hintText: 'abc.123456@dept.ritchennai.edu.in',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _passwordController,
                      obscureText: _obsecureText,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.key),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obsecureText
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obsecureText = !_obsecureText;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _showForgotPasswordDialog,
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(fontSize: 18, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _isLoading
                      ? const CircularProgressIndicator()
                      : GradientButton(text: "LOGIN", onPressed: _login),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't Have Account?"),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SignUp(),
                            ),
                          );
                        },
                        child: const Text(
                          "SignUp",
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
