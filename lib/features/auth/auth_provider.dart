import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_client.dart';
import '../../core/models/user.dart';

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isLoggedIn => user != null;

  AuthState copyWith({User? user, bool? isLoading, String? error}) => AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return const AuthState();

    try {
      final res = await ApiClient.instance.get('/me');
      return AuthState(user: User.fromJson(res.data));
    } catch (_) {
      return const AuthState();
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final res = await ApiClient.instance.post('/login', data: {
        'email': email,
        'password': password,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', res.data['token']);
      state = AsyncValue.data(AuthState(user: User.fromJson(res.data['user'])));
    } catch (e) {
      state = AsyncValue.data(AuthState(error: 'فشل تسجيل الدخول'));
    }
  }

  Future<void> register(String name, String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final res = await ApiClient.instance.post('/register', data: {
        'name': name,
        'email': email,
        'password': password,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', res.data['token']);
      state = AsyncValue.data(AuthState(user: User.fromJson(res.data['user'])));
    } catch (e) {
      state = AsyncValue.data(AuthState(error: 'فشل إنشاء الحساب'));
    }
  }

  Future<void> logout() async {
    try {
      await ApiClient.instance.post('/logout');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    state = const AsyncValue.data(AuthState());
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
