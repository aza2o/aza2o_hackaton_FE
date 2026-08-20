import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/app_state.dart';

const _supabaseUrl = 'https://zfwmwplxezqtxxbgmieb.supabase.co';
const _supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

class AuthProfile {
  const AuthProfile({
    required this.name,
    required this.email,
    required this.privacyConsent,
    required this.aiConsent,
    this.skinType = 'combination',
    this.skinConcerns = const [],
    this.skinSensitivities = const [],
  });

  final String name;
  final String email;
  final bool privacyConsent;
  final bool aiConsent;
  final String skinType;
  final List<String> skinConcerns;
  final List<String> skinSensitivities;
}

class SignUpResult {
  const SignUpResult({required this.requiresEmailConfirmation});
  final bool requiresEmailConfirmation;
}

class AuthService {
  AuthService._();

  static bool _initialized = false;
  static bool get isConfigured => _supabasePublishableKey.isNotEmpty;
  static bool get isAuthenticated =>
      _initialized && Supabase.instance.client.auth.currentSession != null;

  static SupabaseClient get _client {
    if (!_initialized) {
      throw AuthException(
        'Supabase publishable key가 설정되지 않았어요. SUPABASE_PUBLISHABLE_KEY를 확인해주세요.',
      );
    }
    return Supabase.instance.client;
  }

  static Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
    );
    _initialized = true;
  }

  static Future<SignUpResult> signUp({
    required String name,
    required String email,
    required String password,
    required bool privacyConsent,
    required bool aiConsent,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'name': name,
        'privacy_consent': privacyConsent,
        'ai_consent': aiConsent,
      },
    );
    if (response.user == null) {
      throw AuthException('회원가입 결과를 확인하지 못했어요.');
    }
    if (response.session != null) {
      _applyLocalProfile(AuthProfile(
        name: name,
        email: email,
        privacyConsent: privacyConsent,
        aiConsent: aiConsent,
      ));
    }
    return SignUpResult(requiresEmailConfirmation: response.session == null);
  }

  static Future<AuthProfile> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (response.user == null || response.session == null) {
      throw AuthException('로그인 세션을 만들지 못했어요.');
    }
    final profile = await _loadProfile(response.user!);
    _applyLocalProfile(profile);
    await _restoreDailyCheckIns(response.user!.id);
    return profile;
  }

  static Future<void> restoreLocalProfile() async {
    if (!isAuthenticated) return;
    final user = _client.auth.currentUser;
    if (user == null) return;
    final profile = await _loadProfile(user);
    _applyLocalProfile(profile);
    await _restoreDailyCheckIns(user.id);
  }

  static Future<void> signOut() async {
    if (isAuthenticated) await _client.auth.signOut();
  }

  static Future<void> updateConsent({
    required bool privacyConsent,
    required bool aiConsent,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('profiles').update({
      'privacy_consent': privacyConsent,
      'ai_consent': aiConsent,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', user.id);
    await _client.auth.updateUser(
      UserAttributes(data: {
        'privacy_consent': privacyConsent,
        'ai_consent': aiConsent,
      }),
    );
  }

  static Future<void> updateSkinProfile({
    required String skinType,
    required List<String> concerns,
    required List<String> sensitivities,
  }) async {
    if (!isAuthenticated) return;
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('profiles').update({
      'skin_type': skinType,
      'skin_concerns': concerns,
      'skin_sensitivities': sensitivities,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', user.id);
  }

  static Future<void> saveDailyCheckIn({
    required List<String> tags,
    required String note,
  }) async {
    if (!isAuthenticated) return;
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('daily_check_ins').insert({
      'user_id': user.id,
      'tags': tags,
      'note': note,
    });
  }

  static Future<AuthProfile> _loadProfile(User user) async {
    try {
      final row = await _client
          .from('profiles')
          .select('name, email, privacy_consent, ai_consent, skin_type, skin_concerns, skin_sensitivities')
          .eq('id', user.id)
          .single();
      return AuthProfile(
        name: row['name'] as String? ?? '사용자',
        email: row['email'] as String? ?? user.email ?? '',
        privacyConsent: row['privacy_consent'] as bool? ?? false,
        aiConsent: row['ai_consent'] as bool? ?? false,
        skinType: row['skin_type'] as String? ?? 'combination',
        skinConcerns: [for (final value in (row['skin_concerns'] as List? ?? [])) value as String],
        skinSensitivities: [for (final value in (row['skin_sensitivities'] as List? ?? [])) value as String],
      );
    } catch (_) {
      final metadata = user.userMetadata ?? const <String, dynamic>{};
      return AuthProfile(
        name: metadata['name'] as String? ?? '사용자',
        email: user.email ?? '',
        privacyConsent: metadata['privacy_consent'] as bool? ?? false,
        aiConsent: metadata['ai_consent'] as bool? ?? false,
        skinType: metadata['skin_type'] as String? ?? 'combination',
        skinConcerns: [for (final value in (metadata['skin_concerns'] as List? ?? [])) value as String],
        skinSensitivities: [for (final value in (metadata['skin_sensitivities'] as List? ?? [])) value as String],
      );
    }
  }

  static void _applyLocalProfile(AuthProfile profile) {
    AppState.instance.setAuthenticatedUser(name: profile.name, email: profile.email);
    AppState.instance.saveConsent(
      privacy: profile.privacyConsent,
      ai: profile.aiConsent,
    );
    AppState.instance.saveSkinProfile(
      type: profile.skinType,
      concerns: profile.skinConcerns,
      sensitivities: profile.skinSensitivities,
    );
  }

  static Future<void> _restoreDailyCheckIns(String userId) async {
    try {
      final rows = await _client
          .from('daily_check_ins')
          .select('created_at, tags, note')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(90);
      AppState.instance.replaceDailyCheckIns([
        for (final row in rows)
          DailyCheckIn(
            at: DateTime.parse(row['created_at'] as String),
            tags: [for (final tag in (row['tags'] as List? ?? [])) tag as String],
            note: row['note'] as String? ?? '',
          ),
      ]);
    } catch (_) {
      // 테이블이 아직 배포되지 않았거나 오프라인이면 로컬 기록을 유지한다.
    }
  }
}
