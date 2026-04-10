import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _normalizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  String _normalizePassword(String password) {
    return password.trim();
  }

  // Sign Up
  Future<User?> signUp({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: _normalizeEmail(email),
      password: _normalizePassword(password),
    );
    return credential.user;
  }

  // Login
  Future<User?> login({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: _normalizeEmail(email),
      password: _normalizePassword(password),
    );
    return credential.user;
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
  }
}