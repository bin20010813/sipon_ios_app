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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedOpacity(
                    opacity: _leaving ? 0 : 1,
                    duration: const Duration(milliseconds: 220),
                    child: Image.asset(
                      'assest/app_name.png',
                      width: 178,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 7),
                  widget.animateLogoToLogin
                      ? logo
                      : AnimatedOpacity(
                          opacity: _leaving ? 0 : 1,
                          duration: const Duration(milliseconds: 220),
                          child: logo,
                        ),
                ],
              ),
              const SizedBox(height: 30),
              AnimatedOpacity(
                opacity: _leaving ? 0 : 1,
                duration: const Duration(milliseconds: 220),
                child: const Text(
                  '发现身边好酒吧',
                  style: TextStyle(
                    color: Color(0xFF9A3D78),
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
