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
  String get generalSettings => t('通用设置');

  String get reviewTitle => t('评价与反馈');
  String get back => t('返回');
  String get languageTitle => t('语言');
  String get languagePageTitle => t('语言翻译');
  String get languageCurrent => t('当前语言');
  String get languageChinese => t('中文');
  String get languageEnglish => t('英文');
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
  '通用设置': 'General Settings',
  '设置与反馈': 'Settings & Feedback',
  '返回': 'Back',
  '语言': 'Language',
  '当前语言': 'Current Language',
  '中文': 'Chinese',
  '英文': 'English',
  '语言已切换': 'Language updated',
  '用户反馈板': 'Feedback Board',
  '写下你的建议或遇到的问题': 'Write feedback or issues',
  '提交反馈': 'Submit Feedback',
  '请输入反馈内容': 'Please enter feedback first',
  '反馈已提交': 'Feedback submitted',
  '暂无反馈': 'No feedback yet',
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
};
