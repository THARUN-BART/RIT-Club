import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rit_club/pages/User/Home.dart';
import 'package:rit_club/widgets/gradient_button.dart';
import 'package:google_fonts/google_fonts.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _regNumberController = TextEditingController();

  bool _isVerificationSent = false;
  bool _obscurePassword = true;
  bool _isLoading = false;

  String? _selectedDepartment;
  String? _selectedSection;
  bool _isEmailVerified = false;

  final Map<String, List<String>> departmentSections = {
    'cse': ['A', 'B', 'C', 'D', 'E', 'F', 'G'],
    'csbs': ['A', 'B', 'C'],
    'aids': ['A', 'B', 'C', 'D', 'E', 'F'],
    'aiml': ['A', 'B', 'C'],
    'vlsi': ['A', 'B', 'C'],
    'mech': ['A', 'B'],
    'ece': ['A', 'B', 'C'],
    'bioTech': ['A'],
  };

  final RegExp emailRegex = RegExp(
    r'^[a-zA-Z]+\.[0-9]{6}@([a-z]+)\.ritchennai\.edu\.in$',
  );

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

  Future<void> _sendVerification() async {
    final email = _emailController.text.trim();

    final match = emailRegex.firstMatch(email);
    if (match == null) {
      _showMessage(
        "Invalid Email",
        "Use your institutional email (abc.123456@dept.ritchennai.edu.in).",
      );
      return;
    }

    final dept = match.group(1); // captured department from email
    if (!departmentSections.containsKey(dept)) {
      _showMessage("Invalid Dept", "Email contains unknown department.");
      return;
    }

    try {
      setState(() => _isLoading = true);

      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: "temporary123",
      );

      await FirebaseAuth.instance.currentUser?.sendEmailVerification();

      setState(() {
        _isVerificationSent = true;
        _selectedDepartment = dept;
      });

      _showMessage(
        "Verification Sent",
        "Check your inbox to verify your email.",
      );
    } on FirebaseAuthException catch (e) {
      _showMessage("Error", e.message ?? "Something went wrong.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _completeSetup() async {
    final user = FirebaseAuth.instance.currentUser;
    await user?.reload(); // Refresh the user

    if (user == null || !user.emailVerified) {
      _showMessage("Not Verified", "Please verify your email first.");
      return;
    }

    setState(() {
      _isEmailVerified = true;
    });
  }

  Future<void> _finalizeSignup() async {
    final name = _nameController.text.trim();
    final password = _passwordController.text.trim();
    final regNo = _regNumberController.text.trim();
    final section = _selectedSection;

    if (name.isEmpty ||
        password.isEmpty ||
        regNo.length != 13 ||
        section == null) {
      _showMessage("Missing Info", "Please complete all fields properly.");
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    try {
      setState(() => _isLoading = true);

      await user!.updatePassword(password);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'email': user.email,
        'regNo': regNo,
        'department': _selectedDepartment,
        'section': section,
        'role': 'USER',
        'OdCount': 0,
        'FollowedClubs': [],
        'blockUntil': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context)=>HomePage()));
    } catch (e) {
      _showMessage("Error", "Failed to complete signup. Try again.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Sign Up",
          style: GoogleFonts.salsa(fontSize: 32, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 30),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: !_isVerificationSent,
              decoration: const InputDecoration(
                labelText: 'Institutional Email',
                icon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            if (!_isVerificationSent) ...[
              GradientButton(
                text: 'Send Verification Email',
                onPressed: _isLoading ? () {} : _sendVerification,
              ),
            ],
            if (_isVerificationSent && !_isEmailVerified) ...[
              const Text(
                "Check your email and click the verification link",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              GradientButton(
                text: 'I have verified my email',
                onPressed: _isLoading ? () {} : _completeSetup,
              ),
              const SizedBox(height: 15),
              TextButton(
                onPressed: _isLoading ? null : _sendVerification,
                child: const Text('Resend Verification Email'),
              ),
            ],
            if (_isEmailVerified) ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Your Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _regNumberController,
                decoration: const InputDecoration(
                  labelText: '13-digit Reg Number',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              if (_selectedDepartment != null)
                DropdownButtonFormField<String>(
                  value: _selectedSection,
                  items:
                      departmentSections[_selectedDepartment]!
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text("Section $s"),
                            ),
                          )
                          .toList(),
                  onChanged: (val) => setState(() => _selectedSection = val),
                  decoration: const InputDecoration(
                    labelText: "Select Section",
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Set New Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed:
                        () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              GradientButton(
                text: 'Complete Sign Up',
                onPressed: _isLoading ? () {} : _finalizeSignup,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
