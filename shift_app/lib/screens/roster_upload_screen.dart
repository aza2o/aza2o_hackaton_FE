import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/roster_api.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'roster_confirm_screen.dart';

// 로그인 없이 "게스트로 계속하기"로 들어온 경우의 폴백 — 실명이 없어도
// /roster/parse의 user_name(필수)에 뭔가는 보내야 한다.
const _guestUserName = '게스트';

/// 로스터 입력 (Figma 신규 파일 `11:2`). 엑셀 업로드가 1차 우선순위
/// (`SHIFT_개발기획서.md` §5-2) — `POST /roster/parse`(§4-2-1)를 실제로
/// 호출한다. 2차(패턴 선택)는 서버 없이 기존 데모 캘린더로 폴백.
class RosterUploadScreen extends StatefulWidget {
  const RosterUploadScreen({super.key});

  @override
  State<RosterUploadScreen> createState() => _RosterUploadScreenState();
}

class _RosterUploadScreenState extends State<RosterUploadScreen> {
  bool _agreed = false;
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('로스터 입력')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('다음 달 근무표를 넣으면, 넛지를 미리 계산해드려요',
                style: AppTypography.body02.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.xxl),
            _MethodCard(
              rank: '1차 · 추천',
              icon: Icons.description_outlined,
              title: '엑셀 파일 업로드',
              desc: '병동에서 받은 .xlsx / .xls 파일 그대로',
              highlighted: true,
              onTap: _uploading ? null : () => _pickAndUpload(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _MethodCard(
              rank: '2차',
              icon: Icons.calendar_month_outlined,
              title: '패턴 선택 + 캘린더 편집',
              desc: '파일이 없을 때 직접 입력',
              onTap: _uploading ? null : () => _goToDemoConfirm(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _MethodCard(
              rank: '3차 · 준비 중',
              icon: Icons.camera_alt_outlined,
              title: '근무표 사진으로 인식',
              desc: 'OCR로 자동 인식 (곧 지원)',
              disabled: true,
              onTap: null,
            ),
            const SizedBox(height: AppSpacing.xxl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.gray50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('⚠️ 업로드 전 꼭 확인해주세요', style: AppTypography.subtitle04),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '근무표에는 동료들의 일정도 함께 들어있어요. SHIFT는 본인 행만 추출하고, '
                    '원본 파일은 서버에 저장하지 않고 즉시 폐기합니다.',
                    style: AppTypography.caption01
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Checkbox(
                        value: _agreed,
                        activeColor: AppColors.primary500,
                        onChanged: (v) => setState(() => _agreed = v ?? false),
                      ),
                      Text('위 내용을 확인했고 동의합니다', style: AppTypography.caption01),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary500,
                  foregroundColor: AppColors.gray900,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _agreed && !_uploading ? () => _pickAndUpload(context) : null,
                child: _uploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gray900),
                      )
                    : Text('엑셀 파일 선택하기', style: AppTypography.button03),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goToDemoConfirm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RosterConfirmScreen(
          userName: AppState.instance.userName ?? _guestUserName,
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(BuildContext context) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true, // 웹 포함 모든 플랫폼에서 bytes로 받기 위함
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!context.mounted) return;
      _showError(context, '파일을 읽을 수 없어요. 다시 시도해주세요.');
      return;
    }

    if (!context.mounted) return;
    await _upload(context, bytes: bytes, filename: file.name);
  }

  Future<void> _upload(
    BuildContext context, {
    required Uint8List bytes,
    required String filename,
    int? rowIndex,
  }) async {
    setState(() => _uploading = true);
    final now = DateTime.now();
    final result = await parseRosterFile(
      bytes: bytes,
      filename: filename,
      userName: (AppState.instance.userName ?? _guestUserName),
      year: now.year,
      month: now.month,
      rowIndex: rowIndex,
    );
    if (!context.mounted) return;
    setState(() => _uploading = false);

    if (result.isOk) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RosterConfirmScreen(
          year: result.year,
          month: result.month,
          initialShifts: result.shifts,
          unmappedCodes: result.unmappedCodes ?? const [],
          userName: (AppState.instance.userName ?? _guestUserName),
        ),
      ));
      return;
    }

    if (result.needsRowSelection) {
      final chosen = await _showRowSelectionDialog(context, result.candidates ?? const []);
      if (chosen != null) {
        if (!context.mounted) return;
        await _upload(context, bytes: bytes, filename: filename, rowIndex: chosen);
      }
      return;
    }

    _showError(context, result.message ?? '알 수 없는 오류예요');
  }

  Future<int?> _showRowSelectionDialog(
      BuildContext context, List<RosterRowCandidate> candidates) {
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('본인 행을 선택해주세요'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in candidates)
              ListTile(
                title: Text(c.name),
                onTap: () => Navigator.of(context).pop(c.row),
              ),
          ],
        ),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.rank,
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
    this.highlighted = false,
    this.disabled = false,
  });

  final String rank;
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: disabled ? AppColors.gray50 : AppColors.grayWhite,
          borderRadius: BorderRadius.circular(16),
          border: highlighted
              ? Border.all(color: AppColors.primary500, width: 1.5)
              : null,
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: disabled ? AppColors.gray200 : AppColors.primary50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  color: disabled ? AppColors.textPlaceholder : AppColors.primary900),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rank,
                      style: AppTypography.caption03.copyWith(
                        color: disabled
                            ? AppColors.textPlaceholder
                            : AppColors.primary900,
                        fontWeight: FontWeight.w700,
                      )),
                  Text(title,
                      style: AppTypography.subtitle03.copyWith(
                          color: disabled
                              ? AppColors.textPlaceholder
                              : AppColors.textPrimary)),
                  Text(desc,
                      style: AppTypography.caption02
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
