import 'package:flutter/material.dart';

import 'sms_login_page.dart';

class SiponLaunchPage extends StatefulWidget {
  const SiponLaunchPage({
    super.key,
    required this.readyToContinue,
    required this.animateLogoToLogin,
    required this.onContinue,
  });

  final bool readyToContinue;
  final bool animateLogoToLogin;
  final VoidCallback onContinue;

  @override
  State<SiponLaunchPage> createState() => _SiponLaunchPageState();
}

class _SiponLaunchPageState extends State<SiponLaunchPage> {
  static const _brandColor = Color(0xFF563E5C);
  bool _leaving = false;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleTransition();
  }

  @override
  void didUpdateWidget(covariant SiponLaunchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleTransition();
  }

  void _scheduleTransition() {
    if (!widget.readyToContinue || _scheduled) {
      return;
    }

    _scheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 2350), () {
      if (!mounted) {
        return;
      }
      setState(() => _leaving = true);
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted) {
          widget.onContinue();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final logo = Hero(
      tag: siponLoginLogoHeroTag,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.asset(
          'assest/logo.png',
          width: 90,
          height: 90,
          fit: BoxFit.cover,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Transform.translate(
                offset: const Offset(0, -34),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.animateLogoToLogin
                        ? logo
                        : AnimatedOpacity(
                            opacity: _leaving ? 0 : 1,
                            duration: const Duration(milliseconds: 220),
                            child: logo,
                          ),
                    const SizedBox(height: 24),
                    AnimatedOpacity(
                      opacity: _leaving ? 0 : 1,
                      duration: const Duration(milliseconds: 220),
                      child: const Text(
                        'Sip’On',
                        style: TextStyle(
                          color: _brandColor,
                          fontFamily: 'Dubai',
                          fontSize: 42,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AnimatedOpacity(
                      opacity: _leaving ? 0 : 1,
                      duration: const Duration(milliseconds: 220),
                      child: const Text(
                        '酒吧地图',
                        style: TextStyle(
                          color: _brandColor,
                          fontFamily: 'Microsoft YaHei',
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.5,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 34,
              child: AnimatedOpacity(
                opacity: _leaving ? 0 : 1,
                duration: const Duration(milliseconds: 220),
                child: const Text(
                  '杭州探极科技有限公司',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _brandColor,
                    fontFamily: 'Microsoft YaHei',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
