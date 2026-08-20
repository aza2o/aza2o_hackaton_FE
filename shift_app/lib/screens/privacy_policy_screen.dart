import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// 개인정보 처리방침. 가입 화면의 동의 체크에서 열린다.
///
/// ⚠️ 이 앱이 다루는 근무·수면 데이터는 개인정보보호법상 민감정보에
/// 가깝고, AI 리포트는 이 데이터를 **외부 사업자(Google Gemini)로
/// 전송**한다. 그래서 "제3자 제공"과 "국외 이전"을 반드시 명시해야 한다.
/// 실제 서비스 전에는 법무 검토를 받아 이 문구를 확정할 것 —
/// 아래는 현재 코드가 실제로 하는 동작을 사실대로 적은 초안이다.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('개인정보 처리방침')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [
            _Section(
              title: '1. 수집하는 정보',
              body: '• 계정: 이름, 이메일\n'
                  '• 근무: 근무표(날짜별 D/E/N/O), 근무 시각\n'
                  '• 생활: 조명 환경, 크로노타입, 카페인 습관, 취침 기록\n'
                  '• 건강(선택): 수면·심박·HRV 등 HealthKit/Health Connect 데이터',
            ),
            _Section(
              title: '2. 이용 목적',
              body: '일주기 리듬(DLMO)과 수면압력을 계산해 개인화된 취침 '
                  '타이밍과 넛지 알림을 제공하기 위해서만 사용합니다.',
            ),
            _Section(
              title: '3. 보관 위치와 기간',
              body: '계정·근무·생활 정보는 기기 안에만 저장되며, 앱을 삭제하거나 '
                  '로그아웃하면 함께 삭제됩니다. 비밀번호는 저장하지 않습니다.',
            ),
            _Section(
              title: '4. 제3자 제공 및 국외 이전',
              body: 'AI 리포트를 열 때에 한해 아래 정보가 외부로 전송됩니다.\n\n'
                  '• 받는 곳: Google(Gemini API) — 미국 등 국외 서버\n'
                  '• 보내는 항목: 최근 2주 취침 격차(분), 수면 부채(분), '
                  '근무 패턴(D/E/N/O), 사용자가 직접 입력한 컨디션 메모\n'
                  '• 보내지 않는 항목: 이름, 이메일, 비밀번호\n'
                  '• 목적: 리포트 문구 생성\n\n'
                  '근무표 파일을 올릴 때에는 파일이 근무표 파싱 서버로 전송되며, '
                  '파싱 후 저장하지 않습니다.',
            ),
            _Section(
              title: '5. 동의를 거부할 권리',
              body: '동의하지 않아도 앱의 계산·넛지 기능은 사용할 수 있습니다. '
                  '다만 AI 리포트는 외부 전송이 필요해 이용할 수 없습니다.',
            ),
            _Section(
              title: '6. 의료 자문이 아님',
              body: 'SHIFT가 제공하는 취침 타이밍과 넛지는 참고용 정보이며 '
                  '의학적 진단·처방이 아닙니다. 수면 문제가 지속되면 '
                  '전문의와 상담하세요.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.subtitle03),
          const SizedBox(height: AppSpacing.xs),
          Text(body,
              style: AppTypography.body02
                  .copyWith(color: AppColors.textSecondary, height: 1.6)),
        ],
      ),
    );
  }
}
