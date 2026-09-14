import 'package:url_launcher/url_launcher.dart';

/// 用户协议官网地址。
const String kSiponUserAgreementUrl = 'http://www.tanjeek.cn/#/user-agreement';

/// 隐私政策官网地址。
const String kSiponPrivacyPolicyUrl = 'http://www.tanjeek.cn/#/privacy-policy';

/// 在系统浏览器中打开指定的协议官网页面。
///
/// 使用 [LaunchMode.externalApplication] 强制唤起外部浏览器（Safari / Chrome），
/// 返回是否成功启动浏览器。调用方可在失败时给出提示。
Future<bool> openAgreementInBrowser(String url) async {
  final uri = Uri.parse(url);
  if (!await canLaunchUrl(uri)) {
    return false;
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
