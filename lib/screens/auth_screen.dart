import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'dart:ui';


class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLogin = false;
  bool _isLoading = false;
  String? _errorMessage;

  void _submit() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isLogin) {
        await _authService.signIn(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
      } else {
        await _authService.register(
          _emailController.text.trim(),
          _passwordController.text.trim(),
          _nicknameController.text.trim(),
        );
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/chats');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      
      body: Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/background/bgdark.png'),
          fit: BoxFit.fitWidth,
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child:ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.07),
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      //const Icon(Icons.chat, size: 64, color: Color(0xFF2AABEE)),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin ? 'Bentornato!' : 'Benvenuto!',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),

                      if (!_isLogin)
                        TextField(
                          controller: _nicknameController,
                          decoration: InputDecoration(
                            labelText: 'Nickname',
                            labelStyle: const TextStyle(color: Colors.white),
                            prefixIcon: const Icon(Icons.person, color: Colors.white),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      if (!_isLogin) const SizedBox(height: 12),

                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: const TextStyle(color: Colors.white),
                          prefixIcon: const Icon(Icons.email, color: Colors.white),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: const TextStyle(color: Colors.white),
                          prefixIcon: const Icon(Icons.lock, color: Colors.white),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (_errorMessage != null)
                        Text(_errorMessage!, style: const TextStyle(color: Colors.red)),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB77EF1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(_isLogin ? 'Accedi' : 'Registrati'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => setState(() => _isLogin = !_isLogin),
                        child: Text(_isLogin
                            ? 'Non hai un account? Registrati'
                            : 'Hai già un account? Accedi'),
                      ),
                      
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}