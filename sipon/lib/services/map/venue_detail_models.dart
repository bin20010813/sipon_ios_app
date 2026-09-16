import 'map_models.dart';

/// 地点详情页所需的完整数据。
///
/// 在 [MapVenue] 的基础上补充介绍、营业时间、酒款、评价等富文本内容，
/// 供详情面板/页面展示使用。
class VenueDetail {
  /// 创建地点详情模型。
  const VenueDetail({
    required this.venue,
    required this.description,
    required this.latestUpdates,
    required this.businessHours,
    required this.phone,
    required this.priceLevel,
    required this.features,
    required this.signatureDrinks,
    required this.reviews,
    required this.gallery,
    required this.openNow,
    required this.todayKey,
    required this.todayHoursLabel,
    required this.reviewCount,
  });

  /// 基础酒吧信息（id、名称、坐标、评分等）。
  final MapVenue venue;

  /// 酒吧简介，支持多段。
  final List<String> description;

  /// 地点最新动态。
  final List<String> latestUpdates;

  /// 每日营业时间，key 为星期文案，value 为时间段。
  final Map<String, String> businessHours;

  /// 联系电话。
  final String phone;

  /// 人均消费水平，1~4 个 ¥ 符号。
  final String priceLevel;

  /// 特色标签（如“露台”、“现场演出”）。
  final List<String> features;

  /// 招牌酒款列表。
  final List<VenueDrink> signatureDrinks;

  /// 用户评价列表。
  final List<VenueReview> reviews;

  /// 详情页轮播图地址或本地资源路径。
  final List<String> gallery;

  /// 服务端判定好的「当前是否营业中」。
  final bool openNow;

  /// 「今天」对应的星期 key，与 [businessHours] 的 key 匹配。
  final String todayKey;

  /// 今天的营业时段文案，如 "18:00 - 02:00"。
  final String todayHoursLabel;

  /// 评价总数（列表可能只返回前几条）。
  final int reviewCount;
}

/// 单款招牌酒。
class VenueDrink {
  /// 创建酒款模型。
  const VenueDrink({
    required this.name,
    required this.price,
    required this.description,
    required this.tags,
    this.imageAsset,
  });

  /// 酒款名称。
  final String name;

  /// 价格文案，如“¥98”。
  final String price;

  /// 酒款风味描述。
  final String description;

  /// 风味标签，如“果香”、“烈酒感”。
  final List<String> tags;

  /// 可选的封面图本地资源路径。
  final String? imageAsset;
}

/// 分页拉取到的评价结果。
///
/// 详情首屏与「更多评论」翻页共用，[hasMore] 由仓库根据总数判定。
class VenueReviewPage {
  /// 创建分页评价结果。
  const VenueReviewPage({
    required this.reviews,
    required this.totalCount,
    required this.hasMore,
  });

  /// 本页评价列表。
  final List<VenueReview> reviews;

  /// 评价总数（服务端汇总字段或按已拉取量兜底）。
  final int totalCount;

  /// 是否还有下一页评价可加载。
  final bool hasMore;
}

/// 单条用户评价。
class VenueReview {
  /// 创建评价模型。
  const VenueReview({
    required this.nickname,
    required this.rating,
    required this.date,
    required this.content,
    required this.imageAssets,
    this.likeCount = 0,
    this.avatarAsset,
  });

  /// 用户昵称。
  final String nickname;

  /// 评分，0~5。
  final double rating;

  /// 评价日期文案。
  final String date;

  /// 评价正文。
  final String content;

  /// 评价附带的现场或酒款图片。
  final List<String> imageAssets;

  /// 点赞数量。
  final int likeCount;

  /// 可选头像本地资源路径。
  final String? avatarAsset;
}
