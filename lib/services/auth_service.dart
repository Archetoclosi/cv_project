import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

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
    final uid = currentUser?.uid;
    if (uid != null) {
      await _db
          .collection('users')
          .doc(uid)
          .set({'fcmToken': ''}, SetOptions(merge: true));
    }
    await FlutterAppBadger.removeBadge();
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