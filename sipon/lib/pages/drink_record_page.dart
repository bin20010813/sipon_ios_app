import 'package:flutter/material.dart';

import 'language_transform.dart';

class DrinkRecordPage extends StatelessWidget {
  const DrinkRecordPage({super.key});

  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF252229);
  static const Color _muted = Color(0xFF8F8790);

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: IconButton.styleFrom(
                              fixedSize: const Size(42, 42),
                              backgroundColor: const Color(0xFFF8F3F7),
                              foregroundColor: _ink,
                            ),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              text.t('记一笔'),
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const _RecordHero(),
                      const SizedBox(height: 24),
                      Text(
                        text.t('看见你的饮酒习惯'),
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        text.t('记录每一次饮酒，了解频率、偏好和变化趋势。'),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const _RecordFormPreview(),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(text.t('饮酒记录已保存')),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            );
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: Text(text.t('保存记录')),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: _brand,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordHero extends StatelessWidget {
  const _RecordHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 154,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4FB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1F9A3D78)),
      ),
      child: const Center(
        child: Icon(
          Icons.local_bar_rounded,
          color: DrinkRecordPage._brand,
          size: 70,
        ),
      ),
    );
  }
}

class _RecordFormPreview extends StatelessWidget {
  const _RecordFormPreview();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      children: [
        _RecordRow(
          icon: Icons.local_bar_outlined,
          label: text.t('酒款'),
          value: text.t('鸡尾酒'),
        ),
        const SizedBox(height: 10),
        _RecordRow(
          icon: Icons.place_outlined,
          label: text.t('地点'),
          value: text.t('选择酒吧'),
        ),
        const SizedBox(height: 10),
        _RecordRow(
          icon: Icons.payments_outlined,
          label: text.t('花费'),
          value: '¥ 128',
        ),
      ],
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0E7EE)),
      ),
      child: Row(
        children: [
          Icon(icon, color: DrinkRecordPage._brand, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: DrinkRecordPage._ink,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: DrinkRecordPage._muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
