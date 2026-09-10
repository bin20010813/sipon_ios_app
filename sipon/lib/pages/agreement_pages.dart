import 'package:flutter/material.dart';

import 'language_transform.dart';

/// 协议页面类型：用户协议 / 隐私政策。
enum SiponAgreementType {
  /// 用户协议（服务条款）。
  userAgreement,

  /// 隐私政策。
  privacyPolicy,
}

/// 协议章节的结构化内容，中英文分开存放，页面按当前语言渲染。
class SiponAgreementSection {
  /// 创建一个协议章节。
  const SiponAgreementSection({
    required this.titleZh,
    required this.titleEn,
    required this.bodyZh,
    required this.bodyEn,
  });

  /// 章节中文标题。
  final String titleZh;

  /// 章节英文标题。
  final String titleEn;

  /// 章节中文正文段落。
  final List<String> bodyZh;

  /// 章节英文正文段落。
  final List<String> bodyEn;
}

/// 协议更新日期（中文）。
const String kSiponAgreementUpdatedZh = '更新日期：2026 年 9 月 10 日';

/// 协议更新日期（英文）。
const String kSiponAgreementUpdatedEn = 'Last updated: September 10, 2026';

/// 用户协议导言（中文）。
const String _kUserAgreementIntroZh =
    '欢迎你使用 Sipon。本协议是你与 Sipon 运营方之间就使用 Sipon 应用及相关服务所订立的协议。'
    '在注册、登录或使用服务前，请你仔细阅读并充分理解本协议的全部内容，特别是免除或限制责任的条款。'
    '你勾选同意、完成登录或实际使用服务，即视为你已阅读并同意接受本协议的约束。';

/// 用户协议导言（英文）。
const String _kUserAgreementIntroEn =
    'Welcome to Sipon. This Agreement is made between you and the operator of '
    'Sipon regarding your use of the Sipon app and related services. Before '
    'registering, signing in, or using the services, please read and '
    'understand all provisions of this Agreement, especially those that limit '
    'or exclude liability. By accepting, signing in, or actually using the '
    'services, you agree to be bound by this Agreement.';

/// 隐私政策导言（中文）。
const String _kPrivacyPolicyIntroZh =
    'Sipon（以下简称"我们"）非常重视你的个人信息与隐私保护。'
    '本政策说明我们如何收集、使用、存储、共享和保护你的个人信息，以及你可以行使的权利。'
    '一旦你开始使用本应用或同意本政策，即表示你同意我们按照本政策处理你的个人信息。';

/// 隐私政策导言（英文）。
const String _kPrivacyPolicyIntroEn =
    'Sipon ("we", "us") attaches great importance to the protection of your '
    'personal information and privacy. This Policy explains how we collect, '
    'use, store, share, and protect your personal information, and the rights '
    'you may exercise. Once you start using the app or agree to this Policy, '
    'you consent to the processing of your personal information as described '
    'herein.';

/// 用户协议正文内容。
const List<SiponAgreementSection> kSiponUserAgreementSections = [
  SiponAgreementSection(
    titleZh: '协议的接受与变更',
    titleEn: 'Acceptance and Changes',
    bodyZh: [
      '当你按照页面提示完成注册、登录或实际使用本应用服务时，即表示你已阅读并同意接受本协议全部条款的约束。若你不同意本协议的任何内容，请立即停止注册或使用本应用。',
      '我们可能会根据法律法规变化或产品运营需要对本协议进行修订，修订后的协议将在应用内公布。若你继续使用服务，即视为接受修订后的协议；若不同意，请停止使用并可注销账号。',
    ],
    bodyEn: [
      'By completing registration, signing in, or actually using the services as prompted, you confirm that you have read and agreed to be bound by all provisions of this Agreement. If you do not agree with any part of it, please stop registering or using the app immediately.',
      'We may revise this Agreement according to changes in laws and regulations or product needs. The revised Agreement will be published in the app. Continued use of the services means you accept the revised Agreement; if you disagree, please stop using the services and you may deactivate your account.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '服务内容',
    titleEn: 'The Services',
    bodyZh: [
      'Sipon 是一款帮助你记录饮酒体验、发现酒吧场所、管理饮酒预算的应用，具体功能可能包括饮酒记录、偏好画像、酒吧地图与榜单、路线规划、打卡、评价与社区互动等。',
      '我们可能随产品迭代对服务内容进行调整、新增或终止，并会尽可能提前在应用内通知你。部分功能需要你授权相应权限（如位置、通知）后才能使用。',
    ],
    bodyEn: [
      'Sipon is an app that helps you record drinking experiences, discover bars, and manage your drinking budget. Features may include drink logging, taste preferences, bar maps and rankings, route planning, check-ins, reviews, and community features.',
      'We may adjust, add, or discontinue service features as the product evolves, and will give advance notice in the app whenever possible. Some features require you to grant the corresponding permissions (such as location or notifications) before use.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '账号注册与安全',
    titleEn: 'Account Registration and Security',
    bodyZh: [
      '你在注册时应提供真实、准确、完整的信息（如用户名、手机号），并在信息变更时及时更新。',
      '你应妥善保管账号和密码。通过你的账号进行的所有操作均视为你本人行为，由你承担相应责任。',
      '若你发现账号被他人盗用或存在安全风险，请立即联系我们；在通知我们之前造成的损失由你自行承担。',
    ],
    bodyEn: [
      'You should provide true, accurate, and complete information (such as username and phone number) during registration, and update it promptly when it changes.',
      'You are responsible for keeping your account credentials safe. All actions performed through your account are deemed to be performed by you, and you bear the corresponding responsibility.',
      'If you discover that your account has been compromised or is at risk, please contact us immediately. Losses arising before you notify us shall be borne by you.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '用户行为规范',
    titleEn: 'User Conduct',
    bodyZh: [
      '你在使用本应用时应遵守中华人民共和国法律法规及公序良俗。',
      '你不得利用本应用制作、发布、传播违法违规信息，不得侵害他人合法权益，不得骚扰、欺诈其他用户，不得发布虚假或误导性内容。',
      '你不得从事任何危害未成年人身心健康的行为，不得诱导、帮助未成年人获取或饮用酒类产品。',
      '你不得以任何方式干扰本应用的正常运行，或非法获取、存储、处理其他用户的个人信息。',
    ],
    bodyEn: [
      'You shall comply with applicable laws and regulations and public order and good morals when using the app.',
      'You shall not use the app to create, publish, or distribute unlawful content, infringe upon the lawful rights of others, harass or defraud other users, or post false or misleading content.',
      'You shall not engage in any conduct that endangers the physical or mental health of minors, or induce or assist minors in obtaining or consuming alcoholic products.',
      'You shall not interfere with the normal operation of the app in any way, or unlawfully obtain, store, or process other users personal information.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '理性饮酒与健康提示',
    titleEn: 'Responsible Drinking',
    bodyZh: [
      '本应用仅面向年满 18 周岁的用户。若你未满 18 周岁，请立即停止使用本应用。',
      '我们倡导理性饮酒。请勿过量饮酒或酗酒；饮酒后请勿驾驶机动车或从事其他危险活动；孕妇、未成年人及不宜饮酒人群请勿饮酒。',
      '本应用中的统计、榜单、推荐和价目信息仅供参考，不构成医疗、健康或消费建议。如你对饮酒相关的健康状况有疑问，请咨询专业医生。',
    ],
    bodyEn: [
      'This app is intended for users aged 18 or above. If you are under 18, please stop using the app immediately.',
      'We advocate responsible drinking. Do not drink excessively; never drive or engage in hazardous activities after drinking; pregnant women, minors, and people who should avoid alcohol must not drink.',
      'Statistics, rankings, recommendations, and pricing information in the app are for reference only and do not constitute medical, health, or purchasing advice. If you have questions about alcohol-related health issues, please consult a qualified doctor.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '用户内容与授权',
    titleEn: 'User Content and License',
    bodyZh: [
      '你在本应用中发布的内容（如评价、打卡、图片、笔记）的所有权归你或原权利人所有。',
      '为向你提供服务所必需，你授予我们一项免费的、非独占的许可，允许我们在本应用内展示、存储和处理你发布的内容。',
      '你应确保发布的内容合法且不侵犯他人权益；否则由此引发的一切责任由你自行承担，我们有权依法删除相关内容并采取必要措施。',
    ],
    bodyEn: [
      'You or the original rights holder retain ownership of the content you publish in the app (such as reviews, check-ins, photos, and notes).',
      'To the extent necessary to provide the services, you grant us a free, non-exclusive license to display, store, and process the content you publish within the app.',
      'You must ensure that the content you publish is lawful and does not infringe upon the rights of others; otherwise you shall bear all resulting liabilities, and we may delete the relevant content and take necessary measures in accordance with the law.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '知识产权',
    titleEn: 'Intellectual Property',
    bodyZh: [
      '本应用的软件系统、界面设计、商标、标识、图表等内容归 Sipon 运营方或相关权利人所有，受法律法规保护。',
      '未经我们书面许可，任何单位和个人不得复制、转载、传播或以其他商业方式使用上述内容。',
    ],
    bodyEn: [
      'The software, interface design, trademarks, logos, and graphics of the app are owned by the operator of Sipon or the relevant rights holders and are protected by law.',
      'Without our written permission, no organization or individual may copy, reproduce, distribute, or otherwise commercially use the above content.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '免责声明与责任限制',
    titleEn: 'Disclaimers and Limitation of Liability',
    bodyZh: [
      '因不可抗力、基础网络故障、系统维护升级、黑客攻击等非我们过错的原因导致服务中断或数据受损的，我们将尽力协助恢复，但不承担由此造成的损失。',
      '本应用中来自第三方的信息（如酒吧资料、地址、价格、营业状态、用户评价等）仅供参考，我们不对其真实性、完整性和时效性作任何担保，请以实际为准。',
      '在法律允许的最大范围内，我们不对任何间接、附带、特殊或后果性损失承担责任。',
    ],
    bodyEn: [
      'If the services are interrupted or data is damaged due to force majeure, network failures, system maintenance or upgrades, hacker attacks, or other causes not attributable to us, we will make reasonable efforts to assist recovery but shall not be liable for the resulting losses.',
      'Third-party information in the app (such as bar details, addresses, prices, opening status, and user reviews) is for reference only. We make no warranty as to its accuracy, completeness, or timeliness; please rely on actual conditions.',
      'To the maximum extent permitted by law, we shall not be liable for any indirect, incidental, special, or consequential losses.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '服务的变更、中断与终止',
    titleEn: 'Changes, Suspension, and Termination',
    bodyZh: [
      '你可以随时停止使用本应用，并可通过账号安全设置或联系我们申请注销账号。',
      '若你严重违反本协议或法律法规，我们有权视情况暂停、限制或终止向你提供服务，并保留依法追究责任的权利。',
    ],
    bodyEn: [
      'You may stop using the app at any time and may deactivate your account through account security settings or by contacting us.',
      'If you materially breach this Agreement or applicable laws, we may suspend, restrict, or terminate the services provided to you as appropriate, and reserve the right to pursue legal remedies.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '法律适用与争议解决',
    titleEn: 'Governing Law and Dispute Resolution',
    bodyZh: [
      '本协议的订立、履行、解释及争议解决均适用中华人民共和国法律。',
      '因本协议产生的争议，双方应首先友好协商解决；协商不成的，任何一方均可向 Sipon 运营方所在地有管辖权的人民法院提起诉讼。',
    ],
    bodyEn: [
      'The conclusion, performance, interpretation, and dispute resolution of this Agreement shall be governed by the laws of the People s Republic of China.',
      'Disputes arising from this Agreement shall first be resolved through friendly negotiation. If negotiation fails, either party may bring a lawsuit before the people s court with jurisdiction at the place where the operator of Sipon is located.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '联系我们',
    titleEn: 'Contact Us',
    bodyZh: [
      '如你对本协议有任何疑问或建议，可通过服务邮箱 support@sipon.app 或官方网站 sipon.app 与我们联系。',
    ],
    bodyEn: [
      'If you have any questions or suggestions about this Agreement, you can reach us at support@sipon.app or visit sipon.app.',
    ],
  ),
];

/// 隐私政策正文内容。
const List<SiponAgreementSection> kSiponPrivacyPolicySections = [
  SiponAgreementSection(
    titleZh: '我们收集的信息',
    titleEn: 'Information We Collect',
    bodyZh: [
      '账号信息：你在注册或登录时提供的用户名、密码（仅加密存储）、手机号等。',
      '使用数据：你主动创建和保存的饮酒记录、偏好标签、饮酒预算、打卡、评价及上传的图片等。',
      '位置信息：在你授权后收集的大致或精确位置，用于附近酒吧推荐、距离计算、路线规划和城市榜单。',
      '设备与日志信息：设备型号、操作系统版本、应用版本、操作日志、崩溃日志等，用于保障服务安全稳定。',
    ],
    bodyEn: [
      'Account information: the username, password (stored only in encrypted form), and phone number you provide when registering or signing in.',
      'Usage data: the drink logs, taste preferences, budgets, check-ins, reviews, and uploaded photos that you actively create and save.',
      'Location information: approximate or precise location collected after your authorization, used for nearby bar recommendations, distance calculation, route planning, and city rankings.',
      'Device and log information: device model, operating system version, app version, activity logs, and crash logs, used to keep the service secure and stable.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '信息的使用',
    titleEn: 'How We Use Information',
    bodyZh: [
      '创建与管理你的账号，提供登录、身份验证与安全保障。',
      '保存与展示你的饮酒记录、预算和偏好，并基于这些数据提供统计分析与个性化推荐。',
      '在你授权范围内使用位置信息，为你提供附近酒吧、距离与路线规划等功能。',
      '诊断故障、防范安全风险、改进产品功能与用户体验。',
    ],
    bodyEn: [
      'Creating and managing your account, and providing sign-in, authentication, and security protection.',
      'Saving and displaying your drink logs, budgets, and preferences, and providing statistics and personalized recommendations based on this data.',
      'Using location information within the scope of your authorization to provide nearby bars, distances, and route planning.',
      'Diagnosing failures, preventing security risks, and improving product features and user experience.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '信息的存储与保护',
    titleEn: 'Storage and Security',
    bodyZh: [
      '我们采用 HTTPS 加密传输、访问控制、脱敏存储等业界通行的安全技术与管理措施保护你的个人信息。',
      '你的个人信息存储期限以实现本政策所述目的所必需的期限为限；超出必要期限后，我们将依法删除或匿名化处理。',
      '若不幸发生个人信息安全事件，我们将及时启动应急预案、采取补救措施，并以应用内公告等方式告知你。',
    ],
    bodyEn: [
      'We protect your personal information with industry-standard technical and administrative measures such as HTTPS encrypted transmission, access control, and data masking.',
      'Personal information is retained only as long as necessary for the purposes described in this Policy; beyond that period, we will delete or anonymize it in accordance with the law.',
      'In the event of a personal information security incident, we will promptly activate our contingency plan, take remedial measures, and inform you through in-app announcements or other means.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '信息的共享与披露',
    titleEn: 'Sharing and Disclosure',
    bodyZh: [
      '我们不会向任何第三方出售你的个人信息，也不会在未获得你同意的情况下共享可识别你身份的信息（法律法规另有规定的除外）。',
      '仅在以下情形下，我们才会共享必要信息：获得你的明确同意；为提供服务所必需（如短信验证服务）；根据法律法规、司法机关或行政机关的强制性要求。',
    ],
    bodyEn: [
      'We do not sell your personal information to any third party, nor do we share information that can identify you without your consent (except as otherwise required by laws and regulations).',
      'We share necessary information only in the following circumstances: with your explicit consent; where necessary to provide the services (such as SMS verification); or as compelled by laws and regulations or by judicial or administrative authorities.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '你的权利',
    titleEn: 'Your Rights',
    bodyZh: [
      '查询与更正：你可以在账号设置中查看、更正你的账号资料和偏好设置。',
      '删除与导出：你可以删除单条饮酒记录、打卡和评价，也可以在隐私设置中申请导出个人数据或申请注销账号。',
      '撤回同意：你可以随时在系统设置中关闭位置、通知等权限；撤回同意不影响此前基于你同意进行的信息处理活动的效力。',
    ],
    bodyEn: [
      'Access and correction: you can view and correct your profile and preference settings in account settings.',
      'Deletion and export: you can delete individual drink logs, check-ins, and reviews, and you may request an export of your personal data or deactivate your account in privacy settings.',
      'Withdrawal of consent: you can turn off permissions such as location and notifications in system settings at any time; withdrawal does not affect the validity of processing previously carried out based on your consent.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '未成年人保护',
    titleEn: 'Protection of Minors',
    bodyZh: [
      '本应用仅面向成年人提供服务，我们不会主动收集未满 18 周岁未成年人的个人信息。若发现此类信息，我们将尽快删除。',
    ],
    bodyEn: [
      'This app is provided for adults only. We do not knowingly collect personal information from minors under the age of 18. If we become aware of such information, we will delete it as soon as possible.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '政策的更新',
    titleEn: 'Changes to This Policy',
    bodyZh: [
      '我们可能适时对本政策进行修订，并通过应用内公告等显著方式通知你重大变更。本政策的最新版本以应用内展示为准。',
    ],
    bodyEn: [
      'We may update this Policy from time to time and will notify you of material changes through prominent means such as in-app announcements. The latest version of this Policy as displayed in the app shall prevail.',
    ],
  ),
  SiponAgreementSection(
    titleZh: '联系我们',
    titleEn: 'Contact Us',
    bodyZh: [
      '如你对本政策或个人信息保护有任何疑问、意见或投诉，请发送邮件至 support@sipon.app，我们会尽快回复并处理。',
    ],
    bodyEn: [
      'If you have any questions, comments, or complaints about this Policy or personal information protection, please email us at support@sipon.app and we will respond and handle it as soon as possible.',
    ],
  ),
];

/// 协议展示页：按 [type] 渲染《用户协议》或《隐私政策》全文。
class SiponAgreementPage extends StatelessWidget {
  /// 创建协议展示页。
  const SiponAgreementPage({super.key, required this.type});

  /// 要展示的协议类型。
  final SiponAgreementType type;

  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);

  /// 返回当前协议类型的章节列表。
  List<SiponAgreementSection> _sections() {
    return switch (type) {
      SiponAgreementType.userAgreement => kSiponUserAgreementSections,
      SiponAgreementType.privacyPolicy => kSiponPrivacyPolicySections,
    };
  }

  /// 返回当前协议类型的页面标题。
  String _title(SiponAppText text) {
    return switch (type) {
      SiponAgreementType.userAgreement => text.t('用户协议'),
      SiponAgreementType.privacyPolicy => text.t('隐私政策'),
    };
  }

  /// 返回当前协议类型的导言文案。
  String _intro(bool isZh) {
    return switch (type) {
      SiponAgreementType.userAgreement =>
        isZh ? _kUserAgreementIntroZh : _kUserAgreementIntroEn,
      SiponAgreementType.privacyPolicy =>
        isZh ? _kPrivacyPolicyIntroZh : _kPrivacyPolicyIntroEn,
    };
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final isZh = text.isZh;
    final title = _title(text);
    final sections = _sections();

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFF2F3), Color(0xFFFFFCFC), Colors.white],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
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
                        _AgreementTopBar(title: title, back: text.back),
                        const SizedBox(height: 20),
                        _AgreementIntroCard(
                          title: title,
                          updatedAt: isZh
                              ? kSiponAgreementUpdatedZh
                              : kSiponAgreementUpdatedEn,
                          intro: _intro(isZh),
                        ),
                        const SizedBox(height: 14),
                        for (var index = 0; index < sections.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AgreementSectionCard(
                              number: index + 1,
                              section: sections[index],
                              isZh: isZh,
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
      ),
    );
  }
}

/// 协议页顶部返回栏，样式与设置相关页面保持一致。
class _AgreementTopBar extends StatelessWidget {
  /// 创建顶部返回栏。
  const _AgreementTopBar({required this.title, required this.back});

  /// 标题文案。
  final String title;

  /// 返回按钮提示文案。
  final String back;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Tooltip(
            message: back,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: IconButton.styleFrom(
                fixedSize: const Size(40, 40),
                backgroundColor: Colors.white.withValues(alpha: 0.78),
                foregroundColor: SiponAgreementPage._ink,
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SiponAgreementPage._ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 协议导言卡片：展示协议标题、更新日期与导言。
class _AgreementIntroCard extends StatelessWidget {
  /// 创建导言卡片。
  const _AgreementIntroCard({
    required this.title,
    required this.updatedAt,
    required this.intro,
  });

  /// 协议标题。
  final String title;

  /// 更新日期文案。
  final String updatedAt;

  /// 导言正文。
  final String intro;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F9A3D78),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  color: SiponAgreementPage._brand,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SiponAgreementPage._ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              updatedAt,
              style: const TextStyle(
                color: SiponAgreementPage._muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              intro,
              style: const TextStyle(
                color: SiponAgreementPage._ink,
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 协议章节卡片：按序号展示单条章节的标题与正文段落。
class _AgreementSectionCard extends StatelessWidget {
  /// 创建章节卡片。
  const _AgreementSectionCard({
    required this.number,
    required this.section,
    required this.isZh,
  });

  /// 章节序号（从 1 开始）。
  final int number;

  /// 章节内容。
  final SiponAgreementSection section;

  /// 当前是否为中文。
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final paragraphs = isZh ? section.bodyZh : section.bodyEn;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDF7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    number.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      color: SiponAgreementPage._brand,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isZh ? section.titleZh : section.titleEn,
                    style: const TextStyle(
                      color: SiponAgreementPage._ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final paragraph in paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  paragraph,
                  style: const TextStyle(
                    color: SiponAgreementPage._ink,
                    fontSize: 13,
                    height: 1.65,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
