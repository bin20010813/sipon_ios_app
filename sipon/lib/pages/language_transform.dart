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

    final region = _regionEnglishText[source];
    if (region != null) {
      return region;
    }

    if (source.startsWith('当前：')) {
      final city = source.substring(3);
      final cityEn = _regionEnglishText[city] ?? _englishText[city] ?? city;
      return 'Current: $cityEn';
    }
    if (source.startsWith('当前:')) {
      final city = source.substring(3);
      final cityEn = _regionEnglishText[city] ?? _englishText[city] ?? city;
      return 'Current: $cityEn';
    }

    if (source.startsWith('使用本地示例数据:')) {
      return '${t('使用本地示例数据')}:${source.substring('使用本地示例数据:'.length)}';
    }

    // 地图页的距离文案由视野中心实时算出来（mapFormatDistance），取值无穷多，
    // 没法逐条列进 _englishText，按格式转。
    final kilometreMatch = RegExp(r'^约(\d+(?:\.\d+)?)km$').firstMatch(source);
    if (kilometreMatch != null) {
      return 'About ${kilometreMatch.group(1)} km';
    }

    final metreMatch = RegExp(r'^约(\d+)m$').firstMatch(source);
    if (metreMatch != null) {
      return 'About ${metreMatch.group(1)} m';
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

    final attachedImagesMatch = RegExp(r'^已附带 (\d+) 张图片$').firstMatch(source);
    if (attachedImagesMatch != null) {
      return '${attachedImagesMatch.group(1)} image(s) attached';
    }

    final reviewCountMatch = RegExp(r'^查看全部 (\d+) 条评价$').firstMatch(source);
    if (reviewCountMatch != null) {
      return 'See all ${reviewCountMatch.group(1)} reviews';
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
  String get plusSheetTitle => t('想做什么？');
  String get plusSheetHint => t('挑一个开始今晚的微醺');
  String get plusWriteReview => t('写评论');
  String get plusCheckInBar => t('打卡酒吧');
  String get plusPlanRoute => t('规划路线');
  String get plusAddVenue => t('添加酒馆');
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

  /// 礼券徽标：数量来自接口，无数据时显示 0 张。
  String vouchersBadgeCount(int count) {
    if (count <= 0) {
      return isZh ? '0张' : '0 available';
    }
    return isZh ? '$count张可用' : '$count available';
  }

  /// 成就勋章：已解锁数量来自接口，无数据时显示 0 枚。
  // String achievementsUnlockedCount(int count) {
  //   if (count <= 0) {
  //     return isZh ? '0枚' : '0 unlocked';
  //   }
  //   return isZh ? '已解锁$count枚' : '$count unlocked';
  // }
  String get settingsSupport => t('设置与支持');
  String get feedbackAdvice => t('反馈与建议');
  String get languageTransformEntry => t('语言/Language');
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

  /// 供城市选择器等处直接按中英文取值，避免每次走 `t()` 正则分支。
  String cityEn(String zhName) =>
      _regionEnglishText[zhName] ?? _englishText[zhName] ?? zhName;
}

const Map<String, String> _englishText = {
  '首页': 'Home',
  '地图': 'Map',
  '我的': 'Profile',
  '消息': 'Messages',
  '设置': 'Settings',
  '开饮 就现在': 'Turn the SIP ON',
  '用户名': 'Username',
  '请输入用户名': 'Enter username',
  '密码': 'Password',
  '请输入密码（至少 6 位）': 'Enter password (at least 6 characters)',
  '显示密码': 'Show password',
  '隐藏密码': 'Hide password',
  '登录': 'Sign In',
  '我已阅读并同意': 'I have read and agree to the ',
  '和': ' and ',
  '阅读并同意协议': 'Read & Agree',
  '请阅读并同意': 'Please read and agree to the ',
  '，点击协议名称可查看完整内容。': '. Tap a name to view the full text.',
  '不同意': 'Disagree',
  '同意并继续': 'Agree & Continue',
  '无法打开链接，请稍后重试。': 'Unable to open the link. Please try again later.',
  '请求失败，请稍后重试。': 'Request failed. Please try again later.',
  '网络异常，请检查网络和服务地址。':
      'Network error. Please check your connection and server address.',
  '接口响应中未包含 accessToken。': 'The API response did not include an accessToken.',
  '邮箱': 'Email',
  '请输入邮箱': 'Enter your email',
  '请填写正确的邮箱地址': 'Enter a valid email address',
  '验证码': 'Code',
  '请输入验证码': 'Enter 6-digit code',
  '请输入 6 位验证码': 'Please enter the 6-digit code',
  '获取验证码': 'Get Code',
  '发送中…': 'Sending…',
  '验证码已发送，请查收邮箱': 'Code sent. Check your inbox.',
  '验证码发送失败，请稍后重试': 'Failed to send the code. Please try again.',
  '密码登录': 'Password',
  '验证码登录': 'Code',
  '还没有账号？立即注册': "Don't have an account? Sign up",
  '已有账号？去登录': 'Already have an account? Sign in',
  '忘记密码？': 'Forgot password?',
  '重置密码': 'Reset Password',
  '密码已重置，请重新登录': 'Password reset. Please sign in again.',
  '返回登录': 'Back to Sign In',
  '密码登录成功': 'Signed in',
  '注册': 'Sign Up',
  '注册成功': 'Signed up',
  '请输入密码（至少 8 位）': 'Enter password (at least 8 characters)',
  '密码至少 8 位': 'Password must be at least 8 characters',
  '重新获取': 'Resend',
  '琥珀鉴赏家': 'Amber Connoisseur',
  '酒鬼ID： 89829189': 'Sipon ID: 89829189',
  '编辑资料': 'Edit Profile',
  '酒圣勋章': 'Master Badge',
  '我喝过的': 'Tasted',
  '我想喝的': 'Wishlist',
  '酒鬼线路': 'Bar Route',
  '喝酒本金': 'Drink Fund',
  '记一笔': 'Add',
  '想做什么？': 'What do you want to do?',
  '挑一个开始今晚的微醺': 'Pick one to start tonight',
  '写评论': 'Write a Review',
  '打卡酒吧': 'Check in at a Bar',
  '规划路线': 'Plan a Route',
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
  '语言/Language': '语言/Language',
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
  '中文': '中文',
  '英文': 'English',
  '语言已切换': 'Language updated',
  '用户反馈板': 'Feedback Board',
  '留言反馈': 'Message Feedback',
  '写下你的建议或遇到的问题': 'Write feedback or issues',
  '提交反馈': 'Submit Feedback',
  '请输入反馈内容': 'Please enter feedback first',
  '反馈已提交': 'Feedback submitted',
  '添加截图或者视频': 'Add Screenshots or Videos',
  '最多上传 3 张问题截图，便于我们定位页面和异常。':
      'Upload up to 3 issue screenshots so we can locate the page and problem.',
  '最多添加 3 张截图': 'You can add up to 3 screenshots',
  '已添加截图占位': 'Screenshot placeholder added',
  '添加图片': 'Add Images',
  '选择图片来源': 'Choose Image Source',
  '从相册选择': 'Choose from Album',
  '拍照': 'Take Photo',
  '图片选择失败，请重试': 'Failed to pick image. Please retry.',
  '图片上传失败，请重试': 'Image upload failed. Please retry.',
  '图片超过 10MiB 限制，请更换图片': 'Image exceeds 10MiB limit. Please pick another.',
  '提交中...': 'Submitting...',
  '提交失败，请稍后重试': 'Submit failed. Please try again later.',
  '历史反馈': 'Feedback History',
  '历史反馈加载失败': 'Failed to load feedback history',
  '重新加载': 'Reload',
  '暂无反馈记录': 'No feedback yet',
  '功能建议': 'Feature Request',
  '问题反馈': 'Bug Report',
  '处理中': 'Pending',
  '已处理': 'Resolved',
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
  '经典': 'Classic',
  '易饮': 'Easy-drinking',
  '层次': 'Layered',
  '微苦': 'Bitter',
  '安静': 'Quiet',
  '约会推荐': 'Date Night',
  '精酿生啤': 'Craft Beer on Tap',
  '酒头轮换': 'Rotating Taps',
  '啤酒爱好者': 'Beer Geek',
  '下酒小食': 'Bar Snacks',
  '氛围温馨': 'Cozy Vibe',
  'DJ 驻场': 'DJ Sets',
  '舞池': 'Dance Floor',
  '独立乐队': 'Indie Bands',
  '演出': 'Shows',
  '露台座位': 'Terrace',
  '可预订': 'Reservable',
  '无烟区': 'Smoke-free',
  '宠物友好': 'Pet-friendly',
  '无障碍友好': 'Accessible',
  '包厢': 'Private Room',
  '室外吸烟区': 'Outdoor Smoking',
  '波本威士忌、苦精、方糖，经典永不过时。':
      'Bourbon, bitters, sugar — the classic never goes out of style.',
  '干金酒与干味美思的极简平衡。': 'A minimalist balance of dry gin and dry vermouth.',
  '波本、柠檬、糖浆，酸甜利落。': 'Bourbon, lemon, syrup — bright and sharp.',
  '热带水果香气，酒体饱满，苦味柔和。': 'Tropical fruit aroma, full body, soft bitterness.',
  '明快乳酸感，清爽易饮。': 'Bright lactic acidity, crisp and easy.',
  '烘焙咖啡与黑巧克力风味，醇厚收尾。': 'Roasted coffee and dark chocolate, rich finish.',
  '根据当季水果与香草调整的限定酒单。': 'A seasonal list built around fresh fruit and herbs.',
  '红酒、水果与香料的西班牙式微醺。': 'Spanish-style sangria with wine, fruit and spice.',
  '清爽气泡，搭配小食的稳妥之选。': 'Effervescent and safe bet with small bites.',
  '多重基酒混合，派对开场经典款。': 'A mix of spirits — the classic party starter.',
  '渐变色彩，口感甜美。': 'Sunset gradient and a sweet sip.',
  '适合卡座分享，气氛拉满。': 'Bottle service to share, party vibe on full.',
  '简单清爽，适合站着看演出时手持一杯。':
      'Clean and refreshing, perfect while standing at a show.',
  '当晚酒头轮换，具体款式请咨询吧台。': 'Tap rotation changes nightly — ask the bartender.',
  '以演出主题命名的限定款。': 'A limited cocktail named after tonight’s show.',
  '氛围很棒，酒单有惊喜，会再来。': 'Great vibe and a surprising menu. Will come back.',
  '这是一家藏在城市夜色里的清吧，木质吧台与柔和烛光营造出放松的私密氛围。':
      'A quiet lounge tucked into the city night, with a wood bar and soft candlelight.',
  '酒单以经典调酒为骨架，调酒师擅长用本土风味重新诠释熟悉配方，适合想要安静小酌的夜晚。':
      'The menu is built on classics, reinterpreted with local flavors — ideal for a quiet nightcap.',
  '店内拥有多款自酿精酿与国内外小众厂牌生啤，酒头轮换频繁，每次来都能尝到新鲜味道。':
      'House brews and niche craft taps rotate often, so there is always something new to try.',
  '吧台前经常坐满啤酒爱好者，酒保乐于根据你的口味推荐一杯合心意的选择。':
      'The bar is often filled with beer lovers, and the staff is happy to recommend a pint.',
  '餐酒结合的小酒馆，菜单由主厨与调酒师共同设计，主打下酒小食与创意鸡尾酒搭配。':
      'A bistro where food and drinks are co-designed by chef and bartender, pairing bites with creative cocktails.',
  '空间紧凑而温馨，是下班后与朋友边吃边聊的理想落脚点。':
      'Compact and cozy — a perfect spot for post-work bites and chats with friends.',
  '派对氛围十足的夜场，拥有专业灯光与音响系统，周末常有 DJ 驻场与主题派对。':
      'A full-on party venue with pro lighting and sound, plus weekend DJ sets and themed parties.',
  '舞池宽敞，卡座区视野开阔，适合想要释放压力、尽兴跳舞的夜晚。':
      'Spacious dance floor and open booth views for nights when you just want to let go.',
  '以现场音乐为核心的 Livehouse，舞台不大但声场出色，经常邀请独立乐队与音乐人演出。':
      'A livehouse built around live music: small stage, great sound, frequent indie bands and artists.',
  '除演出时段外也提供酒水小食，提前到场还能占到靠前的位置。':
      'Drinks and snacks are served outside showtimes; arrive early for a front-row spot.',
  '服务热情，调酒师很专业，推荐坐在吧台。':
      'Warm service and professional bartenders; grab a seat at the bar.',
  '周末人比较多，建议提前预约。': 'Gets busy on weekends, book ahead.',
  '音乐品味在线，适合放松。': 'Good music taste and a relaxing spot.',
  '人均略高但物有所值，酒的品质在线。': 'A bit pricey but worth it; drinks are quality.',
  '招牌酒层次很完整，第一口和收尾都有变化。':
      'The signature drink evolves nicely from the first sip to the finish.',
  '空间不大但座位舒服，聊天不会觉得吵。':
      'Compact but comfortable, with a good volume for conversation.',
  '酒保推荐得很准，下次想试试季节限定。':
      'The bartender nailed the recommendation; I will try the seasonal menu next.',
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
  '收起地点详情': 'Close place details',
  '类型': 'Type',
  '距离': 'Distance',
  '地点位置': 'Location',
  '未命名酒吧': 'Unnamed Bar',
  '关于': 'About',
  '最新动态': 'Latest Updates',
  '本周末有现场音乐演出': 'Live music this weekend',
  '今日 18:00 开始营业，欢迎提前到店': 'Open from 18:00 today. Walk-ins are welcome.',
  '收藏': 'Save',
  '已收藏': 'Saved',
  '导航': 'Navigate',
  '电话': 'Call',
  '营业时间': 'Opening Hours',
  '补充信息': 'Add info',
  '还没有介绍': 'No intro yet',
  '写下这里的氛围与特色，帮大家种草':
      'Describe the vibe and highlights to help others',
  '还没有动态': 'No updates yet',
  '分享这里的最新活动与消息': 'Share the latest news and events',
  '还没有菜单': 'No menu yet',
  '拍张菜单或补充招牌酒款': 'Upload a menu photo or add signature drinks',
  '还没有评价': 'No reviews yet',
  '说说你的微醺体验，给后来人参考': 'Share your experience with fellow drinkers',
  '感谢共建！信息已提交审核': 'Thanks! Your info was submitted for review',
  '补充地点信息': 'Contribute Info',
  '请至少补充一项内容': 'Please add at least one item',
  '提交补充信息': 'Submit Info',
  '营业时间（可选）': 'Opening Hours (optional)',
  '联系电话（可选）': 'Phone (optional)',
  '例如：周一至周五 18:00-02:00': 'e.g. Mon-Fri 18:00-02:00',
  '例如：18:00-02:00': 'e.g. 18:00-02:00',
  '例如：021-12345678': 'e.g. 021-1234-5678',
  '店面照片': 'Storefront Photos',
  '菜单照片': 'Menu Photos',
  '酒馆介绍': 'Description',
  '氛围、酒单特色、适合什么场景': 'Vibe, drinks, best occasions',
  '提交后会进入审核，通过后展示在地图酒吧地点中。':
      'Submissions are reviewed before showing up on the map.',
  '最多上传 3 张图片': 'Up to 3 photos',
  '地址': 'Address',
  '招牌酒款': 'Signature Drinks',
  '用户评价': 'Reviews',
  '评价': 'Reviews',
  '综合评分': 'Overall rating',
  '条评价': 'reviews',
  '最相关': 'Most relevant',
  '评分从高到低': 'Highest rated',
  '最新到最旧': 'Newest',
  '最旧到最新': 'Oldest',
  '天前': 'days ago',
  '月前': 'months ago',
  '年前': 'years ago',
  '时间未知': 'Unknown time',
  '更多评论': 'More reviews',
  '添加评论': 'Add review',
  '评论发布功能开发中（演示）': 'Review publishing is under development (demo)',
  '营业中': 'Open now',
  '已打烊': 'Closed',
  '人均': 'Avg.',
  '点击导航': 'Tap to navigate',
  '点击拨打': 'Tap to call',
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
  '正在加载地图数据': 'Loading map data',
  '地图数据已加载': 'Map data loaded',
  '当前视野暂无可展示酒吧': 'No bars in this area yet',
  '试着缩小地图或者换个分类看看': 'Try zooming out or picking another category',
  '浅色': 'Light',
  '标准': 'Standard',
  '街道': 'Streets',
  '卫星': 'Satellite',
  '暗色': 'Dark',
  '全部': 'All',
  '点位': 'Points',
  '标签': 'Labels',
  '开': 'On',
  '关': 'Off',
  // 地图 mock 数据按类型派生的标签，补齐还没出现过的几条。
  '自酿啤酒': 'House Brew',
  '微醺小食': 'Small Bites',
  '电音': 'Electronic',
  '乐队演出': 'Band Shows',
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
  'Turn the SIP ON，开饮 就现在': 'Turn the SIP ON，开饮 就现在.',
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
  '危险操作': 'Danger Zone',
  '注销账号': 'Delete Account',
  '永久删除账号与全部本地数据': 'Permanently delete your account and all local data',
  '删除': 'Delete',
  '删除中': 'Deleting',
  '注销后账号数据将被永久删除，且无法恢复。':
      'Your account data will be permanently deleted and cannot be recovered.',
  '账号已注销': 'Account deleted',
  '账号注销失败，请稍后重试': 'Failed to delete account. Please try again later.',
  '邮箱登录已验证，定期更新密码更安全。':
      'Email login verified. Update your password regularly for safety.',
  '加载中': 'Loading',
  '未绑定邮箱': 'No email linked',
  '已验证': 'Verified',
  '通过邮箱验证码重置': 'Reset via email verification code',
  '修改密码': 'Change Password',
  '重置登录密码': 'Reset Login Password',
  '验证码将发送到登录邮箱，至少 8 位新密码。':
      'A code will be sent to your login email. New password needs 8+ characters.',
  '邮箱验证': 'Email Verification',
  '设置新密码': 'Set New Password',
  '请再次输入新密码': 'Confirm your new password',
  '两次输入的新密码不一致': 'The two passwords do not match',
  '确认修改': 'Confirm',
  '正在定位…': 'Locating…',
  '已定位到当前城市': 'Located at current city',
  '检测到您在': 'Detected you are in ',
  '，是否切换？': ', switch?',
  '未获得定位权限，请手动选择城市': 'Location permission not granted, please select manually',
  '定位服务未开启，请手动选择城市': 'Location service disabled, please select manually',
  '定位失败，请手动选择城市': 'Location failed, please select manually',
  '去设置': 'Settings',
  '重试': 'Retry',
};

/// 省市中英文键值：城市选择器左省右市的翻译源。
///
/// 与 `sipon_region_data.dart` 的简称保持 1:1（如“上海”而非“上海市”），
/// 但同时收录带后缀的省级全称以兼容后端 `regions` 返回的写法。
const Map<String, String> _regionEnglishText = {
  // 分组标题
  '热门城市': 'Hot Cities',
  '当前：': 'Current: ',
  // 直辖市城市（平级于省份，单独在下方省份列表之外）
  '上海': 'Shanghai',
  '北京': 'Beijing',
  // 省级全称
  '北京市': 'Beijing',
  '天津市': 'Tianjin',
  '河北省': 'Hebei',
  '山西省': 'Shanxi',
  '内蒙古自治区': 'Inner Mongolia',
  '辽宁省': 'Liaoning',
  '吉林省': 'Jilin',
  '黑龙江省': 'Heilongjiang',
  '上海市': 'Shanghai',
  '江苏省': 'Jiangsu',
  '浙江省': 'Zhejiang',
  '安徽省': 'Anhui',
  '福建省': 'Fujian',
  '江西省': 'Jiangxi',
  '山东省': 'Shandong',
  '河南省': 'Henan',
  '湖北省': 'Hubei',
  '湖南省': 'Hunan',
  '广东省': 'Guangdong',
  '广西壮族自治区': 'Guangxi',
  '海南省': 'Hainan',
  '重庆市': 'Chongqing',
  '四川省': 'Sichuan',
  '贵州省': 'Guizhou',
  '云南省': 'Yunnan',
  '西藏自治区': 'Tibet',
  '陕西省': 'Shaanxi',
  '甘肃省': 'Gansu',
  '青海省': 'Qinghai',
  '宁夏回族自治区': 'Ningxia',
  '新疆维吾尔自治区': 'Xinjiang',
  '香港特别行政区': 'Hong Kong',
  '澳门特别行政区': 'Macao',
  '台湾省': 'Taiwan',
  // 城市简称（地级市全量）
  '石家庄': 'Shijiazhuang',
  '唐山': 'Tangshan',
  '秦皇岛': 'Qinhuangdao',
  '邯郸': 'Handan',
  '邢台': 'Xingtai',
  '保定': 'Baoding',
  '张家口': 'Zhangjiakou',
  '承德': 'Chengde',
  '沧州': 'Cangzhou',
  '廊坊': 'Langfang',
  '衡水': 'Hengshui',
  '太原': 'Taiyuan',
  '大同': 'Datong',
  '阳泉': 'Yangquan',
  '长治': 'Changzhi',
  '晋城': 'Jincheng',
  '朔州': 'Shuozhou',
  '晋中': 'Jinzhong',
  '运城': 'Yuncheng',
  '忻州': 'Xinzhou',
  '临汾': 'Linfen',
  '吕梁': 'Lyuliang',
  '呼和浩特': 'Hohhot',
  '包头': 'Baotou',
  '乌海': 'Wuhai',
  '赤峰': 'Chifeng',
  '通辽': 'Tongliao',
  '鄂尔多斯': 'Ordos',
  '呼伦贝尔': 'Hulunbuir',
  '巴彦淖尔': 'Bayannur',
  '乌兰察布': 'Ulanqab',
  '兴安': 'Hinggan',
  '锡林郭勒': 'Xilingol',
  '阿拉善': 'Alxa',
  '沈阳': 'Shenyang',
  '大连': 'Dalian',
  '鞍山': 'Anshan',
  '抚顺': 'Fushun',
  '本溪': 'Benxi',
  '丹东': 'Dandong',
  '锦州': 'Jinzhou',
  '营口': 'Yingkou',
  '阜新': 'Fuxin',
  '辽阳': 'Liaoyang',
  '盘锦': 'Panjin',
  '铁岭': 'Tieling',
  '朝阳': 'Chaoyang',
  '葫芦岛': 'Huludao',
  '长春': 'Changchun',
  '吉林': 'Jilin',
  '四平': 'Siping',
  '辽源': 'Liaoyuan',
  '通化': 'Tonghua',
  '白山': 'Baishan',
  '松原': 'Songyuan',
  '白城': 'Baicheng',
  '延边': 'Yanbian',
  '哈尔滨': 'Harbin',
  '齐齐哈尔': 'Qiqihar',
  '鸡西': 'Jixi',
  '鹤岗': 'Hegang',
  '双鸭山': 'Shuangyashan',
  '大庆': 'Daqing',
  '伊春': 'Yichun',
  '佳木斯': 'Jiamusi',
  '七台河': 'Qitaihe',
  '牡丹江': 'Mudanjiang',
  '黑河': 'Heihe',
  '绥化': 'Suihua',
  '大兴安岭': "Daxing'anling",
  '南京': 'Nanjing',
  '无锡': 'Wuxi',
  '徐州': 'Xuzhou',
  '常州': 'Changzhou',
  '苏州': 'Suzhou',
  '南通': 'Nantong',
  '连云港': 'Lianyungang',
  '淮安': "Huai'an",
  '盐城': 'Yancheng',
  '扬州': 'Yangzhou',
  '镇江': 'Zhenjiang',
  '泰州': 'Taizhou',
  '宿迁': 'Suqian',
  '温州': 'Wenzhou',
  '嘉兴': 'Jiaxing',
  '湖州': 'Huzhou',
  '绍兴': 'Shaoxing',
  '金华': 'Jinhua',
  '衢州': 'Quzhou',
  '舟山': 'Zhoushan',
  '台州': 'Taizhou',
  '丽水': 'Lishui',
  '合肥': 'Hefei',
  '芜湖': 'Wuhu',
  '蚌埠': 'Bengbu',
  '淮南': 'Huainan',
  '马鞍山': 'Maanshan',
  '淮北': 'Huaibei',
  '铜陵': 'Tongling',
  '安庆': 'Anqing',
  '黄山': 'Huangshan',
  '滁州': 'Chuzhou',
  '阜阳': 'Fuyang',
  '宿州': 'Suzhou',
  '六安': "Lu'an",
  '亳州': 'Bozhou',
  '池州': 'Chizhou',
  '宣城': 'Xuancheng',
  '福州': 'Fuzhou',
  '厦门': 'Xiamen',
  '莆田': 'Putian',
  '三明': 'Sanming',
  '泉州': 'Quanzhou',
  '漳州': 'Zhangzhou',
  '南平': 'Nanping',
  '龙岩': 'Longyan',
  '宁德': 'Ningde',
  '南昌': 'Nanchang',
  '景德镇': 'Jingdezhen',
  '萍乡': 'Pingxiang',
  '九江': 'Jiujiang',
  '新余': 'Xinyu',
  '鹰潭': 'Yingtan',
  '赣州': 'Ganzhou',
  '吉安': "Ji'an",
  '宜春': 'Yichun',
  '抚州': 'Fuzhou',
  '上饶': 'Shangrao',
  '济南': 'Jinan',
  '青岛': 'Qingdao',
  '淄博': 'Zibo',
  '枣庄': 'Zaozhuang',
  '东营': 'Dongying',
  '烟台': 'Yantai',
  '潍坊': 'Weifang',
  '济宁': 'Jining',
  '泰安': "Tai'an",
  '威海': 'Weihai',
  '日照': 'Rizhao',
  '临沂': 'Linyi',
  '德州': 'Dezhou',
  '聊城': 'Liaocheng',
  '滨州': 'Binzhou',
  '菏泽': 'Heze',
  '郑州': 'Zhengzhou',
  '开封': 'Kaifeng',
  '洛阳': 'Luoyang',
  '平顶山': 'Pingdingshan',
  '安阳': 'Anyang',
  '鹤壁': 'Hebi',
  '新乡': 'Xinxiang',
  '焦作': 'Jiaozuo',
  '濮阳': 'Puyang',
  '许昌': 'Xuchang',
  '漯河': 'Luohe',
  '三门峡': 'Sanmenxia',
  '南阳': 'Nanyang',
  '商丘': 'Shangqiu',
  '信阳': 'Xinyang',
  '周口': 'Zhoukou',
  '驻马店': 'Zhumadian',
  '济源': 'Jiyuan',
  '武汉': 'Wuhan',
  '黄石': 'Huangshi',
  '十堰': 'Shiyan',
  '宜昌': 'Yichang',
  '襄阳': 'Xiangyang',
  '鄂州': 'Ezhou',
  '荆门': 'Jingmen',
  '孝感': 'Xiaogan',
  '荆州': 'Jingzhou',
  '黄冈': 'Huanggang',
  '咸宁': 'Xianning',
  '随州': 'Suizhou',
  '恩施': 'Enshi',
  '长沙': 'Changsha',
  '株洲': 'Zhuzhou',
  '湘潭': 'Xiangtan',
  '衡阳': 'Hengyang',
  '邵阳': 'Shaoyang',
  '岳阳': 'Yueyang',
  '常德': 'Changde',
  '张家界': 'Zhangjiajie',
  '益阳': 'Yiyang',
  '郴州': 'Chenzhou',
  '永州': 'Yongzhou',
  '怀化': 'Huaihua',
  '娄底': 'Loudi',
  '湘西': 'Xiangxi',
  '韶关': 'Shaoguan',
  '珠海': 'Zhuhai',
  '汕头': 'Shantou',
  '佛山': 'Foshan',
  '江门': 'Jiangmen',
  '湛江': 'Zhanjiang',
  '茂名': 'Maoming',
  '肇庆': 'Zhaoqing',
  '惠州': 'Huizhou',
  '梅州': 'Meizhou',
  '汕尾': 'Shanwei',
  '河源': 'Heyuan',
  '阳江': 'Yangjiang',
  '清远': 'Qingyuan',
  '东莞': 'Dongguan',
  '中山': 'Zhongshan',
  '潮州': 'Chaozhou',
  '揭阳': 'Jieyang',
  '云浮': 'Yunfu',
  '南宁': 'Nanning',
  '柳州': 'Liuzhou',
  '桂林': 'Guilin',
  '梧州': 'Wuzhou',
  '北海': 'Beihai',
  '防城港': 'Fangchenggang',
  '钦州': 'Qinzhou',
  '贵港': 'Guigang',
  '玉林': 'Yulin',
  '百色': 'Baise',
  '贺州': 'Hezhou',
  '河池': 'Hechi',
  '来宾': 'Laibin',
  '崇左': 'Chongzuo',
  '海口': 'Haikou',
  '三亚': 'Sanya',
  '三沙': 'Sansha',
  '儋州': 'Danzhou',
  '重庆': 'Chongqing',
  '自贡': 'Zigong',
  '攀枝花': 'Panzhihua',
  '泸州': 'Luzhou',
  '德阳': 'Deyang',
  '绵阳': 'Mianyang',
  '广元': 'Guangyuan',
  '遂宁': 'Suining',
  '内江': 'Neijiang',
  '乐山': 'Leshan',
  '南充': 'Nanchong',
  '眉山': 'Meishan',
  '宜宾': 'Yibin',
  '广安': "Guang'an",
  '达州': 'Dazhou',
  '雅安': "Ya'an",
  '巴中': 'Bazhong',
  '资阳': 'Ziyang',
  '阿坝': 'Aba',
  '甘孜': 'Garze',
  '凉山': 'Liangshan',
  '贵阳': 'Guiyang',
  '六盘水': 'Liupanshui',
  '遵义': 'Zunyi',
  '安顺': 'Anshun',
  '毕节': 'Bijie',
  '铜仁': 'Tongren',
  '黔西南': 'Qianxinan',
  '黔东南': 'Qiandongnan',
  '黔南': 'Qiannan',
  '昆明': 'Kunming',
  '曲靖': 'Qujing',
  '玉溪': 'Yuxi',
  '保山': 'Baoshan',
  '昭通': 'Zhaotong',
  '丽江': 'Lijiang',
  '普洱': "Pu'er",
  '临沧': 'Lincang',
  '楚雄': 'Chuxiong',
  '红河': 'Honghe',
  '文山': 'Wenshan',
  '西双版纳': 'Xishuangbanna',
  '大理': 'Dali',
  '德宏': 'Dehong',
  '怒江': 'Nujiang',
  '迪庆': 'Diqing',
  '拉萨': 'Lhasa',
  '日喀则': 'Shigatse',
  '昌都': 'Qamdo',
  '林芝': 'Nyingchi',
  '山南': 'Shannan',
  '那曲': 'Nagqu',
  '阿里': 'Ngari',
  '西安': "Xi'an",
  '铜川': 'Tongchuan',
  '宝鸡': 'Baoji',
  '咸阳': 'Xianyang',
  '渭南': 'Weinan',
  '延安': "Yan'an",
  '汉中': 'Hanzhong',
  '榆林': 'Yulin',
  '安康': 'Ankang',
  '商洛': 'Shangluo',
  '兰州': 'Lanzhou',
  '嘉峪关': 'Jiayuguan',
  '金昌': 'Jinchang',
  '白银': 'Baiyin',
  '天水': 'Tianshui',
  '武威': 'Wuwei',
  '张掖': 'Zhangye',
  '平凉': 'Pingliang',
  '酒泉': 'Jiuquan',
  '庆阳': 'Qingyang',
  '定西': 'Dingxi',
  '陇南': 'Longnan',
  '临夏': 'Linxia',
  '甘南': 'Gannan',
  '西宁': 'Xining',
  '海东': 'Haidong',
  '海北': 'Haibei',
  '黄南': 'Huangnan',
  '海南': 'Hainan',
  '果洛': 'Guoluo',
  '玉树': 'Yushu',
  '海西': 'Haixi',
  '银川': 'Yinchuan',
  '石嘴山': 'Shizuishan',
  '吴忠': 'Wuzhong',
  '固原': 'Guyuan',
  '中卫': 'Zhongwei',
  '乌鲁木齐': 'Urumqi',
  '克拉玛依': 'Karamay',
  '吐鲁番': 'Turpan',
  '哈密': 'Hami',
  '昌吉': 'Changji',
  '博尔塔拉': 'Bortala',
  '巴音郭楞': 'Bayingolin',
  '阿克苏': 'Aksu',
  '克孜勒苏': 'Kizilsu',
  '喀什': 'Kashgar',
  '和田': 'Hotan',
  '伊犁': 'Ili',
  '塔城': 'Tacheng',
  '阿勒泰': 'Altay',
  '香港': 'Hong Kong',
  '澳门': 'Macao',
  '台北': 'Taipei',
  '高雄': 'Kaohsiung',
  '台中': 'Taichung',
  '台南': 'Tainan',
};
