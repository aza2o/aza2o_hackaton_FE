import 'package:flutter/material.dart';
import 'package:shift_circadian_engine/roster/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/app_state.dart';

// 2026-08-20: 원래 프로젝트(zfwmwplxezqtxxbgmieb) 오너 초대가 막혀서 새
// 프로젝트(aza2o-shift-report, ap-northeast-2)로 옮김. profiles/
// daily_check_ins 마이그레이션은 이 프로젝트에 이미 적용돼 있다
// (shift_app/supabase/migrations/). 원 프로젝트 접근 가능해지면 다시
// 합칠지 결정할 것.
const _supabaseUrl = 'https://fthdvkrufjolrfuopvma.supabase.co';
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_NHSYLKAag3fpz0noLFlbQg_KZacuPe2',
);

class DatedRoster {
  const DatedRoster({
    required this.startDate,
    required this.shifts,
    required this.missingIndices,
  });

  final DateTime startDate;
  final List<ShiftType> shifts;
  final Set<int> missingIndices;
}

/// 서버 응답 순서와 무관하게 각 `work_date`를 실제 달력 날짜에 배치한다.
/// 같은 날짜가 중복되면 서버가 먼저 반환한 행을 유지하고, 빠진 날짜나
/// 알 수 없는 근무 코드는 오프로 위조하지 않고 누락 인덱스로 기록한다.
DatedRoster parseDatedRosterRows(Iterable<Map<String, dynamic>> rows) {
  final byDate = <DateTime, ShiftType?>{};
  for (final row in rows) {
    final parsed = DateTime.parse(row['work_date'] as String);
    final date = DateTime(parsed.year, parsed.month, parsed.day);
    byDate.putIfAbsent(
      date,
      () => switch (row['shift_type'] as String?) {
        'D' => ShiftType.day,
        'E' => ShiftType.evening,
        'N' => ShiftType.night,
        'O' => ShiftType.off,
        _ => null,
      },
    );
  }
  if (byDate.isEmpty) {
    throw const FormatException('근무표 날짜 데이터가 비어 있습니다.');
  }

  final dates = byDate.keys.toList()..sort();
  final startDate = dates.first;
  final endDate = dates.last;
  final length = endDate.difference(startDate).inDays + 1;
  final shifts = List<ShiftType>.filled(length, ShiftType.off);
  final missingIndices = <int>{
    for (var index = 0; index < length; index++) index,
  };

  for (final entry in byDate.entries) {
    final shift = entry.value;
    if (shift == null) continue;
    final index = entry.key.difference(startDate).inDays;
    shifts[index] = shift;
    missingIndices.remove(index);
  }

  return DatedRoster(
    startDate: startDate,
    shifts: shifts,
    missingIndices: missingIndices,
  );
}

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

  static const demoAccountId = 'demo@sleepready.app';

  static bool _initialized = false;
  static bool get isConfigured => _supabasePublishableKey.isNotEmpty;
  static String get publishableKey => _supabasePublishableKey;
  static bool get isAuthenticated =>
      AppState.instance.isDemoAccount ||
      (_initialized && Supabase.instance.client.auth.currentSession != null);

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
      _applyLocalProfile(
        AuthProfile(
          name: name,
          email: email,
          privacyConsent: privacyConsent,
          aiConsent: aiConsent,
        ),
      );
    }
    return SignUpResult(requiresEmailConfirmation: response.session == null);
  }

  static Future<AuthProfile> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final response = await _client.auth.signInWithPassword(
      email: normalizedEmail,
      password: password,
    );
    if (response.user == null || response.session == null) {
      throw AuthException('로그인 세션을 만들지 못했어요.');
    }
    final profile = await _loadProfile(response.user!);
    _applyLocalProfile(profile);
    await _restoreDailyCheckIns(response.user!.id);
    if (normalizedEmail == demoAccountId) {
      // 서버의 건강 데이터 조회가 실패해도 근무 달력이 비지 않도록
      // 7~9월 기본 데이터를 먼저 준비한 뒤 서버 데이터로 덮어쓴다.
      await AppState.instance.seedDemoAccount();
      await _restoreDemoDataset(response.user!.id);
    }
    return profile;
  }

  static Future<void> restoreLocalProfile() async {
    if (!isAuthenticated) return;
    final user = _client.auth.currentUser;
    if (user == null) return;
    final profile = await _loadProfile(user);
    _applyLocalProfile(profile);
    await _restoreDailyCheckIns(user.id);
    if ((user.email ?? '').toLowerCase() == demoAccountId) {
      await AppState.instance.seedDemoAccount();
      await _restoreDemoDataset(user.id);
    }
  }

  static Future<void> signOut() async {
    if (_initialized && Supabase.instance.client.auth.currentSession != null) {
      await _client.auth.signOut();
    }
  }

  static Future<void> updateConsent({
    required bool privacyConsent,
    required bool aiConsent,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('profiles')
        .update({
          'privacy_consent': privacyConsent,
          'ai_consent': aiConsent,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', user.id);
    await _client.auth.updateUser(
      UserAttributes(
        data: {'privacy_consent': privacyConsent, 'ai_consent': aiConsent},
      ),
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
    await _client
        .from('profiles')
        .update({
          'skin_type': skinType,
          'skin_concerns': concerns,
          'skin_sensitivities': sensitivities,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', user.id);
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
          .select(
            'name, email, privacy_consent, ai_consent, skin_type, skin_concerns, skin_sensitivities',
          )
          .eq('id', user.id)
          .single();
      return AuthProfile(
        name: row['name'] as String? ?? '사용자',
        email: row['email'] as String? ?? user.email ?? '',
        privacyConsent: row['privacy_consent'] as bool? ?? false,
        aiConsent: row['ai_consent'] as bool? ?? false,
        skinType: row['skin_type'] as String? ?? 'combination',
        skinConcerns: [
          for (final value in (row['skin_concerns'] as List? ?? []))
            value as String,
        ],
        skinSensitivities: [
          for (final value in (row['skin_sensitivities'] as List? ?? []))
            value as String,
        ],
      );
    } catch (_) {
      final metadata = user.userMetadata ?? const <String, dynamic>{};
      return AuthProfile(
        name: metadata['name'] as String? ?? '사용자',
        email: user.email ?? '',
        privacyConsent: metadata['privacy_consent'] as bool? ?? false,
        aiConsent: metadata['ai_consent'] as bool? ?? false,
        skinType: metadata['skin_type'] as String? ?? 'combination',
        skinConcerns: [
          for (final value in (metadata['skin_concerns'] as List? ?? []))
            value as String,
        ],
        skinSensitivities: [
          for (final value in (metadata['skin_sensitivities'] as List? ?? []))
            value as String,
        ],
      );
    }
  }

  static void _applyLocalProfile(AuthProfile profile) {
    AppState.instance.setAuthenticatedUser(
      name: profile.name,
      email: profile.email,
    );
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
            tags: [
              for (final tag in (row['tags'] as List? ?? [])) tag as String,
            ],
            note: row['note'] as String? ?? '',
          ),
      ]);
    } catch (_) {
      // 테이블이 아직 배포되지 않았거나 오프라인이면 로컬 기록을 유지한다.
    }
  }

  static Future<void> _restoreDemoDataset(String userId) async {
    List<Map<String, dynamic>> rosterRows = [];
    List<Map<String, dynamic>> healthRows = [];
    try {
      rosterRows = await _client
          .from('roster_entries')
          .select('work_date, shift_type')
          .eq('user_id', userId);
    } catch (_) {
      // 근무표 조회 실패는 로컬 7~9월 데모 시드로 복구한다.
    }

    try {
      healthRows = await _client
          .from('health_daily_metrics')
          .select(
            'metric_date, sleep_start, sleep_end, sleep_minutes, hrv_z, resting_heart_rate, source',
          )
          .eq('user_id', userId)
          .order('metric_date');
    } catch (_) {
      // 건강 데이터가 없어도 근무표 복원은 계속한다.
    }

    try {
      AppState.instance.saveOnboarding(
        shiftTimings: const {
          ShiftType.day: (
            TimeOfDay(hour: 7, minute: 0),
            TimeOfDay(hour: 15, minute: 0),
          ),
          ShiftType.evening: (
            TimeOfDay(hour: 15, minute: 0),
            TimeOfDay(hour: 23, minute: 0),
          ),
          ShiftType.night: (
            TimeOfDay(hour: 23, minute: 0),
            TimeOfDay(hour: 7, minute: 0),
          ),
        },
        workplaceLighting: 'bright',
        bedroomLighting: 'blackout',
        chronotype: 'evening',
        caffeineCutoff: const TimeOfDay(hour: 14, minute: 0),
        caffeineServings: 2,
      );

      final demoRosterRows = rosterRows.where((row) {
        final date = DateTime.parse(row['work_date'] as String);
        return !date.isBefore(DateTime(2026, 7, 1)) &&
            date.isBefore(DateTime(2026, 10, 1));
      }).toList();
      if (demoRosterRows.isNotEmpty) {
        final datedRoster = parseDatedRosterRows(demoRosterRows);
        AppState.instance.saveRoster(
          datedRoster.shifts,
          startDate: datedRoster.startDate,
          missingIndices: datedRoster.missingIndices,
        );
      }

      AppState.instance.replaceSyncedHealthMetrics([
        for (final row in healthRows)
          SyncedHealthMetric(
            date: DateTime.parse(row['metric_date'] as String),
            sleepStart: DateTime.parse(row['sleep_start'] as String),
            sleepEnd: DateTime.parse(row['sleep_end'] as String),
            sleepMinutes: row['sleep_minutes'] as int,
            hrvZ: (row['hrv_z'] as num?)?.toDouble(),
            restingHeartRate: (row['resting_heart_rate'] as num?)?.toDouble(),
            source: row['source'] as String? ?? 'demo_watch',
          ),
      ]);
    } catch (_) {
      // 행 변환 중 문제가 생기면 기존 로컬 데모를 유지한다.
    }
  }
}
