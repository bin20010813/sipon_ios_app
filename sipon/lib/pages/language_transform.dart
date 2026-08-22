import 'package:flutter/material.dart';

enum SiponLanguage { zh, en }

class SiponLanguageController extends ChangeNotifier {
  SiponLanguageController({SiponLanguage initialLanguage = SiponLanguage.zh})
    : _language = initialLanguage;

  SiponLanguage _language;

  SiponLanguage get language => _language;

  void setLanguage(SiponLanguage language) {
    if (_language == language) {
      return;
    }

    _language = language;
    notifyListeners();
  }
}

class SiponLanguageScope extends InheritedNotifier<SiponLanguageController> {
  const SiponLanguageScope({
    super.key,
    required SiponLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static SiponLanguageController controllerOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SiponLanguageScope>();
    assert(scope?.notifier != null, 'SiponLanguageScope was not found.');
    return scope!.notifier!;
  }

  static SiponLanguage languageOf(BuildContext context) {
    return controllerOf(context).language;
  }

  static SiponAppText textOf(BuildContext context) {
    return SiponAppText(languageOf(context));
  }
}

class SiponAppText {
  const SiponAppText(this.language);

  final SiponLanguage language;

  bool get isZh => language == SiponLanguage.zh;

  String t(String source) {
    if (isZh || source.isEmpty) {
      return source;
    }

    final direct = _englishText[source];
    if (direct != null) {
      return direct;
    }

    if (source.startsWith('地图数据加载失败:')) {
      return '${t('地图数据加载失败')}:${source.substring('地图数据加载失败:'.length)}';
    }

    if (source.startsWith('使用本地示例数据:')) {
      return '${t('使用本地示例数据')}:${source.substring('使用本地示例数据:'.length)}';
    }

    final screenshotMatch = RegExp(r'^截图 (\d+)$').firstMatch(source);
    if (screenshotMatch != null) {
      return 'Screenshot ${screenshotMatch.group(1)}';
    }

    final attachedScreenshotMatch = RegExp(
      r'^已附加 (\d+) 张截图$',
    ).firstMatch(source);
    if (attachedScreenshotMatch != null) {
      return '${attachedScreenshotMatch.group(1)} screenshots attached';
    }

    final kilometerMatch = RegExp(r'^约(.+)公里$').firstMatch(source);
    if (kilometerMatch != null) {
      return 'About ${kilometerMatch.group(1)} km';
    }

    return source;
  }

  String get appTitle => 'Sipon';
  String get homeTab => t('首页');
  String get mapTab => t('地图');
  String get profileTab => t('我的');

  String get messages => t('消息');
  String get settings => t('设置');
  String get profileName => t('琥珀鉴赏家');
  String get profileId => t('酒鬼ID： 89829189');
  String get editProfile => t('编辑资料');
  String get badgeTitle => t('酒圣勋章');

  String get drank => t('我喝过的');
  String get wishList => t('我想喝的');
  String get route => t('酒鬼线路');
  String get drinkBudget => t('喝酒本金');
  String get addRecord => t('记一笔');
  String get monthlySpend => t('本月支出');
  String get monthlyDeltaPrefix => t('较上月  ');
  String get monthlyBudget => t('本月预算');
  String get remainingBudget => t('剩余预算');
  String get editBudget => t('设置月预算');
  String get enterBudget => t('请输入月预算金额');
  String get budgetUpdated => t('预算已更新');
  String get noComparison => t('暂无对比');
  String get monthlyRecords => t('本月记录');
  String get noRecords => t('本月还没有记账记录');
  String get cancel => t('取消');
  String get confirm => t('确定');
  String get benefits => t('权益');
  String get membership => t('Sipon会员');
  String get vouchers => t('我的礼券');
  String get vouchersBadge => t('3张可用');
  String get achievements => t('成就勋章');
  String get achievementsUnlocked => t('已解锁8枚');
  String get settingsSupport => t('设置与支持');
  String get feedbackAdvice => t('反馈与建议');
  String get languageTransformEntry => t('语言翻译');
  String get reviewEntry => t('评价与反馈');
  String get accountSecurity => t('账号安全');
  String get preferenceSelection => t('偏好选择');
  String get notificationSettings => t('通知设置');
  String get privacySettings => t('隐私设置');
  String get praiseUs => t('夸一下');
  String get featureFeedback => t('功能反馈');
  String get aboutUs => t('关于我们');
  String get generalSettings => t('通用设置');

  String get reviewTitle => t('评价与反馈');
  String get back => t('返回');
  String get languageTitle => t('语言');
  String get languagePageTitle => t('语言翻译');
  String get languageCurrent => t('当前语言');
  String get languageChinese => t('中文');
  String get languageEnglish => t('En');
  String get languageChanged => t('语言已切换');
  String get feedbackBoardTitle => t('用户反馈板');
  String get feesdbackBoardTitle => feedbackBoardTitle;
  String get feedbackHint => t('写下你的建议或遇到的问题');
  String get submitFeedback => t('提交反馈');
  String get feedbackRequired => t('请输入反馈内容');
  String get feedbackSent => t('反馈已提交');
  String get feedbackEmpty => t('暂无反馈');
  String get rateTitle => t('为我们评分');
  String get ratingPrompt => t('选择你的评分');
  String get submitRating => t('提交评分');
  String get ratingRequired => t('请先选择评分');
  String get ratingSent => t('评分已提交');

  String ratingValue(int rating) {
    if (rating == 0) {
      return t('未评分');
    }

    return isZh ? '$rating 星' : '$rating stars';
  }

  String feedbackNumber(int number) {
    return isZh ? '反馈 #$number' : 'Feedback #$number';
  }
}

const Map<String, String> _englishText = {
  '首页': 'Home',
  '地图': 'Map',
  '我的': 'Profile',
  '消息': 'Messages',
  '设置': 'Settings',
  '欢迎来到 SipOn': 'Welcome to SipOn',
  '记录每一次微醺。':
      'keep tracking every drink.',
  '用户名': 'Username',
  '请输入用户名': 'Enter username',
  '密码': 'Password',
  '请输入密码（至少 6 位）': 'Enter password (at least 6 characters)',
  '显示密码': 'Show password',
  '隐藏密码': 'Hide password',
  '登录': 'Sign In',
  '登录即代表你已阅读并同意用户协议和隐私政策':
      'By signing in, you agree to the User Agreement and Privacy Policy',
  '请求失败，请稍后重试。': 'Request failed. Please try again later.',
  '网络异常，请检查网络和服务地址。':
      'Network error. Please check your connection and server address.',
  '接口响应中未包含 accessToken。': 'The API response did not include an accessToken.',
  '琥珀鉴赏家': 'Amber Connoisseur',
  '酒鬼ID： 89829189': 'Sipon ID: 89829189',
  '编辑资料': 'Edit Profile',
  '酒圣勋章': 'Master Badge',
  '我喝过的': 'Tasted',
  '我想喝的': 'Wishlist',
  '酒鬼线路': 'Bar Route',
  '喝酒本金': 'Drink Fund',
  '记一笔': 'Add',
  '本月支出': 'Monthly Spend',
  '较上月  ': 'vs last month  ',
  '本月预算': 'Monthly Budget',
  '剩余预算': 'Remaining',
  '设置月预算': 'Set Budget',
  '请输入月预算金额': 'Enter monthly budget',
  '预算已更新': 'Budget updated',
  '暂无对比': 'No comparison',
  '本月记录': 'Monthly Records',
  '本月还没有记账记录': 'No records this month',
  '账单': 'Bills',
  '关闭': 'Close',
  '年': 'Year',
  '月': 'Month',
  '日': 'Day',
  '周': 'Week',
  '当日': 'Today',
  '本周': 'This Week',
  '本月': 'This Month',
  '支出': 'Spend',
  '上个月': 'Previous month',
  '下个月': 'Next month',
  '消费趋势': 'Spending Trend',
  '最近 7 个有消费记录的日期': 'Latest 7 spending days',
  '消费构成': 'Spending Breakdown',
  '全部明细': 'All Records',
  '明细': ' Records',
  '笔': ' entries',
  '当天还没有记账记录': 'No records on this day',
  '预算': 'Budget',
  '剩余': 'Remaining',
  '记账笔数': 'Entries',
  '消费天数': 'Spending Days',
  '日均消费': 'Daily Average',
  '暂无统计数据': 'No statistics yet',
  '取消': 'Cancel',
  '确定': 'Confirm',
  '权益': 'Benefits',
  'Sipon会员': 'Sipon Membership',
  '我的礼券': 'Vouchers',
  '3张可用': '3 available',
  '成就勋章': 'Achievements',
  '已解锁8枚': '8 unlocked',
  '设置与支持': 'Settings & Support',
  '反馈与建议': 'Feedback',
  '语言翻译': 'Language',
  '评价与反馈': 'Reviews & Feedback',
  '账号安全': 'Account Security',
  '偏好选择': 'Preferences',
  '通知设置': 'Notifications',
  '隐私设置': 'Privacy',
  '夸一下': 'Like Us',
  '功能反馈': 'Feature Feedback',
  '关于我们': 'About Us',
  '通用设置': 'General Settings',
  '设置与反馈': 'Settings & Feedback',
  '返回': 'Back',
  '语言': 'Language',
  '当前语言': 'Current Language',
  '中文': 'Chinese',
  '英文': 'English',
  '语言已切换': 'Language updated',
  '用户反馈板': 'Feedback Board',
  '留言反馈': 'Message Feedback',
  '写下你的建议或遇到的问题': 'Write feedback or issues',
  '提交反馈': 'Submit Feedback',
  '请输入反馈内容': 'Please enter feedback first',
  '反馈已提交': 'Feedback submitted',
  '暂无反馈': 'No feedback yet',
  '添加截图': 'Add Screenshots',
  '最多上传 3 张问题截图，便于我们定位页面和异常。':
      'Upload up to 3 issue screenshots so we can locate the page and problem.',
  '最多添加 3 张截图': 'You can add up to 3 screenshots',
  '已添加截图占位': 'Screenshot placeholder added',
  '添加': 'Add',
  '为我们评分': 'Rate Us',
  '选择你的评分': 'Choose your rating',
  '提交评分': 'Submit Rating',
  '请先选择评分': 'Please choose a rating first',
  '评分已提交': 'Rating submitted',
  '未评分': 'Not rated',
  '搜索': 'Search',
  '更多': 'More',
  '酒吧推荐': 'Bars of the day',
  '调酒师故事': 'Bartender Stories',
  '鸡尾酒推荐': 'Cocktails of the day',
  '朗姆酒': 'Rum',
  '热带甜感': 'Tropical sweetness',
  '伏特加': 'Vodka',
  '莹质酒': 'Crystal clear',
  '冰块': 'Ice',
  '风味辅助': 'Flavor support',
  '金酒': 'Gin',
  '草本香气': 'Herbal aroma',
  '经典复古': 'Classic retro',
  '地下酒吧': 'Speakeasy',
  '庙前冰室（Hope & Sesame）': 'Hope & Sesame',
  '鸡尾酒吧': 'Cocktail Bar',
  '中式复古风': 'Chinese Retro',
  '越秀区庙前西街 48 号': '48 Miaoqian West St, Yuexiu',
  '约2460公里': 'About 2,460 km',
  '清吧': 'Lounge',
  '精酿': 'Craft Beer',
  '派对': 'Party',
  '从孟买到上海\n用风味连接世界':
      'From Mumbai to Shanghai\nconnecting worlds through flavor',
  '风味探索': 'Flavor Discovery',
  '文化融合': 'Cultural Fusion',
  '创意表达': 'Creative Expression',
  '经典技巧': 'Classic Technique',
  '优雅平衡': 'Elegant Balance',
  '东方灵感': 'Eastern Inspiration',
  '女性魅力': 'Feminine Charm',
  '全国TOP10酒吧': 'Top 10 Bars in China',
  'Speak Low（彼楼）': 'Speak Low',
  '隐藏式 speakeasy，调酒专业，复古氛围浓。':
      'Hidden speakeasy with polished cocktails and a strong retro mood.',
  '北京顶级鸡尾酒清吧，经典调酒极强。': 'Top Beijing cocktail lounge with excellent classics.',
  'Play House 电音夜店': 'Play House Club',
  '百大夜店，超大舞池，顶级电音和舞美。':
      'Top club with a huge dance floor, electronic music, and stage production.',
  '广州Top10': 'Guangzhou Top 10',
  '庙前冰室': 'Hope & Sesame',
  '岭南灵感和复古调酒。': 'Lingnan inspiration and retro cocktails.',
  '庙前酒馆': 'Miaoqian Tavern',
  '烛光、木质吧台和威士忌。': 'Candlelight, a wood bar, and whisky.',
  '天台酒廊': 'Rooftop Lounge',
  '城市夜景与招牌特调。': 'City night views and signature cocktails.',
  '白俄罗斯': 'White Russian',
  '冷战的硬核浪漫': 'Cold War romance in a glass',
  '黑俄罗斯': 'Black Russian',
  '流动的咖啡冰淇淋': 'Flowing coffee ice cream',
  '流动的咖啡烈酒': 'Flowing coffee liqueur',
  '地图数据加载失败': 'Map data failed to load',
  '使用本地示例数据': 'Using local sample data',
  '正在加载接口数据...': 'Loading API data...',
  '接口未返回可展示酒吧': 'The API returned no displayable bars',
  '地址待补充': 'Address pending',
  '距离待计算': 'Distance pending',
  '未命名酒吧': 'Unnamed Bar',
  '搜索喜欢的酒或者酒吧...': 'Search drinks or bars...',
  '记录每一次微醺': 'Record every tipsy moment',
  '正在整理你的饮酒记录...': 'Preparing your drinking records...',
  '载入完成': 'Ready',
  '看见你的饮酒习惯': 'See your drinking habits',
  '记录每一次饮酒，了解频率、偏好和变化趋势。':
      'Log every drink to understand frequency, preferences, and trends.',
  '少一点模糊印象，多一点清楚记录': 'Less fuzzy memory, more clear records',
  '选择城市': 'Choose City',
  '城市变化后会刷新附近酒吧和地图内容': 'Changing city refreshes nearby bars and map content',
  '上海': 'Shanghai',
  '北京': 'Beijing',
  '深圳': 'Shenzhen',
  '广州': 'Guangzhou',
  '成都': 'Chengdu',
  '杭州': 'Hangzhou',
  '保存记录': 'Save Record',
  '饮酒记录已保存': 'Drink record saved',
  '酒款': 'Drink',
  '地点': 'Place',
  '花费': 'Spend',
  '鸡尾酒': 'Cocktail',
  '选择酒吧': 'Choose Bar',
  '地图工具': 'Map Tools',
  '地图样式': 'Map Style',
  '数据图层': 'Data Layers',
  '回到总览': 'Overview',
  '聚焦城区': 'Focus Downtown',
  '等待地图': 'Waiting for map',
  '正在加载 marker、GeoJSON 与热力图': 'Loading markers, GeoJSON, and heatmap',
  '地图数据已加载': 'Map data loaded',
  '浅色': 'Light',
  '标准': 'Standard',
  '街道': 'Streets',
  '卫星': 'Satellite',
  '暗色': 'Dark',
  '全部': 'All',
  '点位': 'Points',
  '热力': 'Heatmap',
  '上海市黄浦区复兴中路 579': '579 Fuxing Middle Rd, Huangpu, Shanghai',
  '约2.0km': 'About 2.0 km',
  '约1.7km': 'About 1.7 km',
  '约2.4km': 'About 2.4 km',
  '约2.8km': 'About 2.8 km',
  '经典吧台': 'Classic Bar',
  '上海市黄浦区巨鹿路 158': '158 Julu Rd, Huangpu, Shanghai',
  '经典调酒': 'Classic Cocktails',
  '上海市黄浦区淮海中路 333': '333 Huaihai Middle Rd, Huangpu, Shanghai',
  '现场音乐': 'Live Music',
  '巨鹿路小酒馆': 'Julu Road Bistro',
  '复兴公园酒廊': 'Fuxing Park Lounge',
  '思南精酿': 'Sinan Craft',
  '新天地热区 A': 'Xintiandi Hot Zone A',
  '新天地热区 B': 'Xintiandi Hot Zone B',
  '复兴中路热区 A': 'Fuxing Middle Rd Hot Zone A',
  '黄陂南路热区 A': 'Huangpi South Rd Hot Zone A',
  '选择酒款': 'Choose Drink',
  '请选择酒款': 'Please choose a drink',
  '请选择地点': 'Please choose a place',
  '请填写花费金额': 'Please enter the amount',
  '金额需大于 0': 'Amount must be greater than 0',
  '杯数': 'Cups',
  '日期': 'Date',
  '今天': 'Today',
  '评分': 'Rating',
  '备注': 'Note',
  '添加备注': 'Add a note',
  '记录详情': 'Record details',
  '本笔记账': 'This record',
  '记录已保存到本地': 'Record saved locally',
  '其他地点': 'Other place',
  '输入自定义地点': 'Enter a custom place',
  '啤酒': 'Beer',
  '威士忌': 'Whisky',
  '红酒': 'Wine',
  '香槟': 'Champagne',
  '清酒': 'Sake',
  '烈酒': 'Spirit',
  '其他': 'Other',
  '共': 'Total',
  '杯': 'cups',
  '选择地点': 'Choose Place',
  '搜索酒吧': 'Search bars',
  '账号保护中': 'Account protected',
  '当前登录环境稳定，建议保持安全提醒开启。':
      'Your current login environment is stable. Keep security alerts on.',
  '登录与验证': 'Login & Verification',
  '手机号': 'Phone Number',
  '186****0921': '186****0921',
  '更换': 'Change',
  '登录密码': 'Login Password',
  '上次更新 32 天前': 'Updated 32 days ago',
  '修改': 'Edit',
  '生物识别解锁': 'Biometric Unlock',
  '用于快速进入 Sipon': 'Quickly unlock Sipon',
  '异地登录提醒': 'New Location Alert',
  '发现新设备登录时通知你': 'Notify you when a new device signs in',
  '退出登录': 'Log Out',
  '清除本机登录状态': 'Clear this device sign-in state',
  '退出': 'Log Out',
  '退出中': 'Logging out',
  '退出后需要重新登录才能继续使用 Sipon。':
      'You will need to sign in again to continue using Sipon.',
  '偏好画像': 'Preference Profile',
  '这些选择会用于后续推荐酒款、酒吧和活动。':
      'These choices will shape drink, bar, and event recommendations.',
  '口味标签': 'Flavor Tags',
  '清爽': 'Fresh',
  '果香': 'Fruity',
  '烟熏': 'Smoky',
  '草本': 'Herbal',
  '甜口': 'Sweet',
  '烈酒感': 'Spirit-forward',
  '常用场景': 'Common Scenes',
  '微醺小聚': 'Casual Tipsy Meetup',
  '安静清吧': 'Quiet Lounge',
  '餐酒搭配': 'Food Pairing',
  '派对夜场': 'Party Night',
  '消息偏好': 'Message Preferences',
  '先保存在本地状态，接口接入后同步到账号。':
      'Saved locally for now, then synced to your account after APIs are connected.',
  '通知类型': 'Notification Types',
  '活动与预约': 'Events & Bookings',
  '酒吧活动、预约状态和到店提醒': 'Bar events, booking status, and arrival reminders',
  '预算提醒': 'Budget Alerts',
  '月预算接近上限时提醒': 'Remind you when monthly spending nears the limit',
  '个性推荐': 'Personalized Picks',
  '推荐酒款、酒吧和榜单内容': 'Recommended drinks, bars, and rankings',
  '系统通知': 'System Notifications',
  '账号、安全和服务变更通知': 'Account, security, and service updates',
  '隐私控制': 'Privacy Controls',
  '管理资料展示、饮酒记录和位置权限的可见范围。':
      'Manage profile visibility, drink records, and location permissions.',
  '可见范围': 'Visibility',
  '公开个人主页': 'Public Profile',
  '允许其他用户看到昵称、头像和勋章': 'Let others see your nickname, avatar, and badges',
  '展示饮酒记录': 'Show Drink Records',
  '仅展示酒款与地点，不展示金额': 'Only show drinks and places, not amounts',
  '使用位置推荐': 'Use Location Recommendations',
  '用于附近酒吧、距离和城市榜单': 'Used for nearby bars, distance, and city rankings',
  '数据管理': 'Data Management',
  '导出个人数据': 'Export Personal Data',
  '饮酒记录、预算和偏好设置': 'Drink records, budgets, and preferences',
  '申请': 'Request',
  '清除本地缓存': 'Clear Local Cache',
  '不影响账号云端数据': 'Does not affect account cloud data',
  '清理': 'Clear',
  '感谢你的喜欢': 'Thanks for liking Sipon',
  '等应用商店链接接入后，这里会跳转到评分页。':
      'This will open the app store rating page after the link is connected.',
  '可以这样支持我们': 'Ways to Support Us',
  '去应用商店评分': 'Rate in App Store',
  '给 Sipon 一个真实评分': 'Give Sipon an honest rating',
  '待接入': 'Pending',
  '分享给朋友': 'Share with Friends',
  '邀请朋友一起记录微醺地图': 'Invite friends to record their tipsy map',
  '写下使用体验': 'Write Your Experience',
  '告诉我们哪一刻让你觉得好用': 'Tell us what felt useful',
  '填写': 'Write',
  '记录饮酒偏好，发现附近好酒吧，管理每一次微醺。':
      'Track drink preferences, find nearby bars, and manage every tipsy moment.',
  '产品信息': 'Product Info',
  '版本': 'Version',
  '服务邮箱': 'Support Email',
  '官方网站': 'Official Website',
  '协议与说明': 'Terms & Notes',
  '用户协议': 'User Agreement',
  '查看 Sipon 服务条款': 'View Sipon service terms',
  '查看': 'View',
  '隐私政策': 'Privacy Policy',
  '了解数据收集与使用方式': 'Learn how data is collected and used',
};
