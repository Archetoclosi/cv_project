import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _rememberMeKey = 'remember_me';

  User? get currentUser => _auth.currentUser;

  // Persistent login preference
  Future<void> saveRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, true);
  }

  Future<void> clearRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberMeKey);
  }

  Future<bool> isRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    final flag = prefs.getBool(_rememberMeKey) ?? false;
    return flag && currentUser != null;
  }

  // Registrazione con email, password e nickname
  Future<void> register(String email, String password, String nickname) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Salva il profilo utente su Firestore
    await _db.collection('users').doc(credential.user!.uid).set({
      'nickname': nickname,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Login
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // Logout
  Future<void> signOut() async {
    await clearRememberMe();
    await _auth.signOut();
  }

  // Recupera il nickname dell'utente corrente
  Future<String> getNickname() async {
    final doc = await _db
        .collection('users')
        .doc(currentUser!.uid)
        .get();
    return doc.data()?['nickname'] ?? 'Anonimo';
  }
}