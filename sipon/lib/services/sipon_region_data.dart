/// 全国省市内置数据：城市选择器（左省右市）的兜底数据源。
///
/// 设计说明：
/// - 纯 Dart，不依赖 Flutter，可被地图坐标、城市控制器、选择器同时引用。
/// - 城市名统一用简称（不带“市 / 盟 / 地区 / 自治州”后缀），与后端
///   `GET /api/cities` 返回的短名风格保持一致（如“上海”而不是“上海市”）。
/// - 坐标为城市中心概略经纬度（WGS-84）：省会与热门城市较精确，其余地级市
///   为概略值，用于切换城市时相机 `flyTo` 落点，误差在城市级缩放下可接受。
/// - 后端 `GET /api/regions` 可用时由 [SiponRegionRepository] 按名称匹配补
///   坐标，内置表只做兜底，不强求与后端完全一致。
class SiponCityEntry {
  const SiponCityEntry(this.name, this.nameEn, this.longitude, this.latitude);

  final String name;
  final String nameEn;
  final double longitude;
  final double latitude;
}

class SiponProvinceEntry {
  const SiponProvinceEntry(this.name, this.nameEn, this.cities);

  final String name;
  final String nameEn;
  final List<SiponCityEntry> cities;
}

/// 首页 / 地图页城市选择器左上角默认展示的热门城市。
const List<String> siponHotCityNames = [
  '上海',
  '北京',
  '广州',
  '深圳',
  '成都',
  '杭州',
  '重庆',
  '武汉',
  '西安',
  '南京',
  '苏州',
  '厦门',
  '长沙',
  '青岛',
  '天津',
  '宁波',
];

const List<SiponProvinceEntry> siponProvinces = [
  SiponProvinceEntry('北京市', 'Beijing', [SiponCityEntry('北京', 'Beijing', 116.41, 39.90)]),
  SiponProvinceEntry('天津市', 'Tianjin', [SiponCityEntry('天津', 'Tianjin', 117.20, 39.13)]),
  SiponProvinceEntry('河北省', 'Hebei', [
    SiponCityEntry('石家庄', 'Shijiazhuang', 114.51, 38.04),
    SiponCityEntry('唐山', 'Tangshan', 118.18, 39.63),
    SiponCityEntry('秦皇岛', 'Qinhuangdao', 119.60, 39.94),
    SiponCityEntry('邯郸', 'Handan', 114.54, 36.61),
    SiponCityEntry('邢台', 'Xingtai', 114.50, 37.07),
    SiponCityEntry('保定', 'Baoding', 115.46, 38.87),
    SiponCityEntry('张家口', 'Zhangjiakou', 114.89, 40.82),
    SiponCityEntry('承德', 'Chengde', 117.96, 40.95),
    SiponCityEntry('沧州', 'Cangzhou', 116.84, 38.31),
    SiponCityEntry('廊坊', 'Langfang', 116.68, 39.54),
    SiponCityEntry('衡水', 'Hengshui', 115.67, 37.74),
  ]),
  SiponProvinceEntry('山西省', 'Shanxi', [
    SiponCityEntry('太原', 'Taiyuan', 112.55, 37.87),
    SiponCityEntry('大同', 'Datong', 113.30, 40.08),
    SiponCityEntry('阳泉', 'Yangquan', 113.58, 37.86),
    SiponCityEntry('长治', 'Changzhi', 113.12, 36.19),
    SiponCityEntry('晋城', 'Jincheng', 112.85, 35.49),
    SiponCityEntry('朔州', 'Shuozhou', 112.43, 39.33),
    SiponCityEntry('晋中', 'Jinzhong', 112.74, 37.69),
    SiponCityEntry('运城', 'Yuncheng', 111.01, 35.03),
    SiponCityEntry('忻州', 'Xinzhou', 112.73, 38.42),
    SiponCityEntry('临汾', 'Linfen', 111.52, 36.09),
    SiponCityEntry('吕梁', 'Lyuliang', 111.14, 37.52),
  ]),
  SiponProvinceEntry('内蒙古自治区', 'Inner Mongolia', [
    SiponCityEntry('呼和浩特', 'Hohhot', 111.75, 40.84),
    SiponCityEntry('包头', 'Baotou', 109.84, 40.66),
    SiponCityEntry('乌海', 'Wuhai', 106.79, 39.66),
    SiponCityEntry('赤峰', 'Chifeng', 118.89, 42.26),
    SiponCityEntry('通辽', 'Tongliao', 122.24, 43.65),
    SiponCityEntry('鄂尔多斯', 'Ordos', 109.78, 39.61),
    SiponCityEntry('呼伦贝尔', 'Hulunbuir', 119.77, 49.21),
    SiponCityEntry('巴彦淖尔', 'Bayannur', 107.39, 40.76),
    SiponCityEntry('乌兰察布', 'Ulanqab', 113.13, 40.99),
    SiponCityEntry('兴安', 'Hinggan', 122.07, 46.08),
    SiponCityEntry('锡林郭勒', 'Xilingol', 116.09, 43.94),
    SiponCityEntry('阿拉善', 'Alxa', 105.71, 38.85),
  ]),
  SiponProvinceEntry('辽宁省', 'Liaoning', [
    SiponCityEntry('沈阳', 'Shenyang', 123.43, 41.80),
    SiponCityEntry('大连', 'Dalian', 121.61, 38.91),
    SiponCityEntry('鞍山', 'Anshan', 122.99, 41.11),
    SiponCityEntry('抚顺', 'Fushun', 123.96, 41.88),
    SiponCityEntry('本溪', 'Benxi', 123.77, 41.29),
    SiponCityEntry('丹东', 'Dandong', 124.35, 40.13),
    SiponCityEntry('锦州', 'Jinzhou', 121.13, 41.09),
    SiponCityEntry('营口', 'Yingkou', 122.24, 40.67),
    SiponCityEntry('阜新', 'Fuxin', 121.67, 42.02),
    SiponCityEntry('辽阳', 'Liaoyang', 123.24, 41.27),
    SiponCityEntry('盘锦', 'Panjin', 122.07, 41.12),
    SiponCityEntry('铁岭', 'Tieling', 123.73, 42.22),
    SiponCityEntry('朝阳', 'Chaoyang', 120.45, 41.57),
    SiponCityEntry('葫芦岛', 'Huludao', 120.84, 40.71),
  ]),
  SiponProvinceEntry('吉林省', 'Jilin', [
    SiponCityEntry('长春', 'Changchun', 125.32, 43.89),
    SiponCityEntry('吉林', 'Jilin', 126.55, 43.84),
    SiponCityEntry('四平', 'Siping', 124.35, 43.17),
    SiponCityEntry('辽源', 'Liaoyuan', 125.14, 42.89),
    SiponCityEntry('通化', 'Tonghua', 125.94, 41.73),
    SiponCityEntry('白山', 'Baishan', 126.42, 42.55),
    SiponCityEntry('松原', 'Songyuan', 124.83, 45.14),
    SiponCityEntry('白城', 'Baicheng', 122.84, 45.62),
    SiponCityEntry('延边', 'Yanbian', 129.51, 42.89),
  ]),
  SiponProvinceEntry('黑龙江省', 'Heilongjiang', [
    SiponCityEntry('哈尔滨', 'Harbin', 126.53, 45.80),
    SiponCityEntry('齐齐哈尔', 'Qiqihar', 123.92, 47.35),
    SiponCityEntry('鸡西', 'Jixi', 130.97, 45.30),
    SiponCityEntry('鹤岗', 'Hegang', 130.28, 47.35),
    SiponCityEntry('双鸭山', 'Shuangyashan', 131.14, 46.65),
    SiponCityEntry('大庆', 'Daqing', 125.10, 46.59),
    SiponCityEntry('伊春', 'Yichun', 128.84, 47.73),
    SiponCityEntry('佳木斯', 'Jiamusi', 130.32, 46.80),
    SiponCityEntry('七台河', 'Qitaihe', 131.00, 45.77),
    SiponCityEntry('牡丹江', 'Mudanjiang', 129.63, 44.55),
    SiponCityEntry('黑河', 'Heihe', 127.53, 50.25),
    SiponCityEntry('绥化', 'Suihua', 126.97, 46.65),
    SiponCityEntry('大兴安岭', 'Daxing\'anling', 124.71, 50.42),
  ]),
  SiponProvinceEntry('上海市', 'Shanghai', [SiponCityEntry('上海', 'Shanghai', 121.47, 31.22)]),
  SiponProvinceEntry('江苏省', 'Jiangsu', [
    SiponCityEntry('南京', 'Nanjing', 118.80, 32.06),
    SiponCityEntry('无锡', 'Wuxi', 120.30, 31.57),
    SiponCityEntry('徐州', 'Xuzhou', 117.18, 34.26),
    SiponCityEntry('常州', 'Changzhou', 119.97, 31.81),
    SiponCityEntry('苏州', 'Suzhou', 120.62, 31.30),
    SiponCityEntry('南通', 'Nantong', 120.86, 32.01),
    SiponCityEntry('连云港', 'Lianyungang', 119.22, 35.61),
    SiponCityEntry('淮安', 'Huai\'an', 119.02, 33.61),
    SiponCityEntry('盐城', 'Yancheng', 120.16, 33.35),
    SiponCityEntry('扬州', 'Yangzhou', 119.42, 32.39),
    SiponCityEntry('镇江', 'Zhenjiang', 119.43, 32.19),
    SiponCityEntry('泰州', 'Taizhou', 119.93, 32.46),
    SiponCityEntry('宿迁', 'Suqian', 118.28, 33.96),
  ]),
  SiponProvinceEntry('浙江省', 'Zhejiang', [
    SiponCityEntry('杭州', 'Hangzhou', 120.16, 30.29),
    SiponCityEntry('宁波', 'Ningbo', 121.55, 29.88),
    SiponCityEntry('温州', 'Wenzhou', 120.70, 27.99),
    SiponCityEntry('嘉兴', 'Jiaxing', 120.76, 30.75),
    SiponCityEntry('湖州', 'Huzhou', 120.09, 30.89),
    SiponCityEntry('绍兴', 'Shaoxing', 120.58, 30.03),
    SiponCityEntry('金华', 'Jinhua', 119.65, 29.08),
    SiponCityEntry('衢州', 'Quzhou', 118.86, 28.97),
    SiponCityEntry('舟山', 'Zhoushan', 122.21, 29.99),
    SiponCityEntry('台州', 'Taizhou', 121.42, 28.66),
    SiponCityEntry('丽水', 'Lishui', 119.93, 28.47),
  ]),
  SiponProvinceEntry('安徽省', 'Anhui', [
    SiponCityEntry('合肥', 'Hefei', 117.28, 31.86),
    SiponCityEntry('芜湖', 'Wuhu', 118.43, 31.35),
    SiponCityEntry('蚌埠', 'Bengbu', 117.36, 32.92),
    SiponCityEntry('淮南', 'Huainan', 117.02, 32.63),
    SiponCityEntry('马鞍山', 'Maanshan', 118.54, 31.67),
    SiponCityEntry('淮北', 'Huaibei', 116.80, 33.96),
    SiponCityEntry('铜陵', 'Tongling', 117.81, 30.95),
    SiponCityEntry('安庆', 'Anqing', 117.06, 30.53),
    SiponCityEntry('黄山', 'Huangshan', 118.34, 29.71),
    SiponCityEntry('滁州', 'Chuzhou', 118.32, 32.30),
    SiponCityEntry('阜阳', 'Fuyang', 115.69, 32.89),
    SiponCityEntry('宿州', 'Suzhou', 116.96, 33.65),
    SiponCityEntry('六安', 'Lu\'an', 116.52, 31.73),
    SiponCityEntry('亳州', 'Bozhou', 115.78, 33.86),
    SiponCityEntry('池州', 'Chizhou', 117.49, 30.67),
    SiponCityEntry('宣城', 'Xuancheng', 118.76, 30.94),
  ]),
  SiponProvinceEntry('福建省', 'Fujian', [
    SiponCityEntry('福州', 'Fuzhou', 119.30, 26.08),
    SiponCityEntry('厦门', 'Xiamen', 118.09, 24.48),
    SiponCityEntry('莆田', 'Putian', 119.01, 25.43),
    SiponCityEntry('三明', 'Sanming', 117.64, 26.26),
    SiponCityEntry('泉州', 'Quanzhou', 118.68, 24.88),
    SiponCityEntry('漳州', 'Zhangzhou', 117.65, 24.51),
    SiponCityEntry('南平', 'Nanping', 118.18, 26.64),
    SiponCityEntry('龙岩', 'Longyan', 117.03, 25.08),
    SiponCityEntry('宁德', 'Ningde', 119.55, 26.67),
  ]),
  SiponProvinceEntry('江西省', 'Jiangxi', [
    SiponCityEntry('南昌', 'Nanchang', 115.86, 28.68),
    SiponCityEntry('景德镇', 'Jingdezhen', 117.18, 29.27),
    SiponCityEntry('萍乡', 'Pingxiang', 113.85, 27.62),
    SiponCityEntry('九江', 'Jiujiang', 116.00, 29.71),
    SiponCityEntry('新余', 'Xinyu', 114.92, 27.82),
    SiponCityEntry('鹰潭', 'Yingtan', 117.07, 28.26),
    SiponCityEntry('赣州', 'Ganzhou', 114.93, 25.83),
    SiponCityEntry('吉安', 'Ji\'an', 114.98, 27.11),
    SiponCityEntry('宜春', 'Yichun', 114.42, 27.80),
    SiponCityEntry('抚州', 'Fuzhou', 116.33, 27.97),
    SiponCityEntry('上饶', 'Shangrao', 117.94, 28.45),
  ]),
  SiponProvinceEntry('山东省', 'Shandong', [
    SiponCityEntry('济南', 'Jinan', 117.10, 36.65),
    SiponCityEntry('青岛', 'Qingdao', 120.38, 36.07),
    SiponCityEntry('淄博', 'Zibo', 118.05, 36.82),
    SiponCityEntry('枣庄', 'Zaozhuang', 117.32, 34.81),
    SiponCityEntry('东营', 'Dongying', 118.67, 37.43),
    SiponCityEntry('烟台', 'Yantai', 121.45, 37.46),
    SiponCityEntry('潍坊', 'Weifang', 119.16, 36.71),
    SiponCityEntry('济宁', 'Jining', 116.59, 35.41),
    SiponCityEntry('泰安', 'Tai\'an', 117.09, 36.20),
    SiponCityEntry('威海', 'Weihai', 122.11, 37.51),
    SiponCityEntry('日照', 'Rizhao', 119.53, 35.42),
    SiponCityEntry('临沂', 'Linyi', 118.36, 35.10),
    SiponCityEntry('德州', 'Dezhou', 116.31, 37.47),
    SiponCityEntry('聊城', 'Liaocheng', 115.99, 36.46),
    SiponCityEntry('滨州', 'Binzhou', 117.97, 37.38),
    SiponCityEntry('菏泽', 'Heze', 115.48, 35.24),
  ]),
  SiponProvinceEntry('河南省', 'Henan', [
    SiponCityEntry('郑州', 'Zhengzhou', 113.63, 34.75),
    SiponCityEntry('开封', 'Kaifeng', 114.31, 34.80),
    SiponCityEntry('洛阳', 'Luoyang', 112.45, 34.62),
    SiponCityEntry('平顶山', 'Pingdingshan', 113.19, 33.77),
    SiponCityEntry('安阳', 'Anyang', 114.39, 36.10),
    SiponCityEntry('鹤壁', 'Hebi', 114.30, 35.75),
    SiponCityEntry('新乡', 'Xinxiang', 113.93, 35.30),
    SiponCityEntry('焦作', 'Jiaozuo', 113.23, 35.24),
    SiponCityEntry('濮阳', 'Puyang', 115.03, 35.76),
    SiponCityEntry('许昌', 'Xuchang', 113.86, 34.02),
    SiponCityEntry('漯河', 'Luohe', 114.02, 33.58),
    SiponCityEntry('三门峡', 'Sanmenxia', 111.20, 34.77),
    SiponCityEntry('南阳', 'Nanyang', 112.53, 32.99),
    SiponCityEntry('商丘', 'Shangqiu', 115.66, 34.41),
    SiponCityEntry('信阳', 'Xinyang', 114.09, 32.15),
    SiponCityEntry('周口', 'Zhoukou', 114.70, 33.63),
    SiponCityEntry('驻马店', 'Zhumadian', 114.02, 32.98),
    SiponCityEntry('济源', 'Jiyuan', 112.59, 35.07),
  ]),
  SiponProvinceEntry('湖北省', 'Hubei', [
    SiponCityEntry('武汉', 'Wuhan', 114.30, 30.59),
    SiponCityEntry('黄石', 'Huangshi', 115.04, 30.20),
    SiponCityEntry('十堰', 'Shiyan', 110.80, 32.63),
    SiponCityEntry('宜昌', 'Yichang', 111.29, 30.69),
    SiponCityEntry('襄阳', 'Xiangyang', 112.12, 32.01),
    SiponCityEntry('鄂州', 'Ezhou', 114.88, 30.39),
    SiponCityEntry('荆门', 'Jingmen', 112.20, 31.04),
    SiponCityEntry('孝感', 'Xiaogan', 113.92, 30.92),
    SiponCityEntry('荆州', 'Jingzhou', 112.23, 30.35),
    SiponCityEntry('黄冈', 'Huanggang', 114.87, 30.45),
    SiponCityEntry('咸宁', 'Xianning', 114.32, 29.84),
    SiponCityEntry('随州', 'Suizhou', 113.38, 31.69),
    SiponCityEntry('恩施', 'Enshi', 109.49, 30.27),
  ]),
  SiponProvinceEntry('湖南省', 'Hunan', [
    SiponCityEntry('长沙', 'Changsha', 112.94, 28.23),
    SiponCityEntry('株洲', 'Zhuzhou', 113.13, 27.83),
    SiponCityEntry('湘潭', 'Xiangtan', 112.94, 27.83),
    SiponCityEntry('衡阳', 'Hengyang', 112.57, 26.90),
    SiponCityEntry('邵阳', 'Shaoyang', 111.47, 27.24),
    SiponCityEntry('岳阳', 'Yueyang', 113.13, 29.37),
    SiponCityEntry('常德', 'Changde', 111.70, 29.03),
    SiponCityEntry('张家界', 'Zhangjiajie', 110.48, 29.12),
    SiponCityEntry('益阳', 'Yiyang', 112.33, 28.55),
    SiponCityEntry('郴州', 'Chenzhou', 113.02, 25.77),
    SiponCityEntry('永州', 'Yongzhou', 111.61, 26.42),
    SiponCityEntry('怀化', 'Huaihua', 110.00, 27.57),
    SiponCityEntry('娄底', 'Loudi', 111.95, 27.70),
    SiponCityEntry('湘西', 'Xiangxi', 109.73, 28.26),
  ]),
  SiponProvinceEntry('广东省', 'Guangdong', [
    SiponCityEntry('广州', 'Guangzhou', 113.26, 23.13),
    SiponCityEntry('韶关', 'Shaoguan', 113.60, 24.81),
    SiponCityEntry('深圳', 'Shenzhen', 114.06, 22.55),
    SiponCityEntry('珠海', 'Zhuhai', 113.58, 22.27),
    SiponCityEntry('汕头', 'Shantou', 116.69, 23.35),
    SiponCityEntry('佛山', 'Foshan', 113.12, 23.02),
    SiponCityEntry('江门', 'Jiangmen', 113.08, 22.59),
    SiponCityEntry('湛江', 'Zhanjiang', 110.36, 21.27),
    SiponCityEntry('茂名', 'Maoming', 110.93, 21.67),
    SiponCityEntry('肇庆', 'Zhaoqing', 112.47, 23.05),
    SiponCityEntry('惠州', 'Huizhou', 114.42, 23.11),
    SiponCityEntry('梅州', 'Meizhou', 116.13, 24.29),
    SiponCityEntry('汕尾', 'Shanwei', 115.38, 22.79),
    SiponCityEntry('河源', 'Heyuan', 114.70, 23.74),
    SiponCityEntry('阳江', 'Yangjiang', 111.98, 21.86),
    SiponCityEntry('清远', 'Qingyuan', 113.06, 23.68),
    SiponCityEntry('东莞', 'Dongguan', 113.75, 23.02),
    SiponCityEntry('中山', 'Zhongshan', 113.39, 22.52),
    SiponCityEntry('潮州', 'Chaozhou', 116.62, 23.66),
    SiponCityEntry('揭阳', 'Jieyang', 116.37, 23.55),
    SiponCityEntry('云浮', 'Yunfu', 112.04, 22.92),
  ]),
  SiponProvinceEntry('广西壮族自治区', 'Guangxi', [
    SiponCityEntry('南宁', 'Nanning', 108.32, 22.82),
    SiponCityEntry('柳州', 'Liuzhou', 109.43, 24.33),
    SiponCityEntry('桂林', 'Guilin', 110.29, 25.27),
    SiponCityEntry('梧州', 'Wuzhou', 111.28, 23.48),
    SiponCityEntry('北海', 'Beihai', 109.12, 21.48),
    SiponCityEntry('防城港', 'Fangchenggang', 108.35, 21.61),
    SiponCityEntry('钦州', 'Qinzhou', 108.65, 21.98),
    SiponCityEntry('贵港', 'Guigang', 109.60, 23.11),
    SiponCityEntry('玉林', 'Yulin', 110.18, 22.64),
    SiponCityEntry('百色', 'Baise', 106.61, 23.90),
    SiponCityEntry('贺州', 'Hezhou', 111.57, 24.40),
    SiponCityEntry('河池', 'Hechi', 108.06, 24.70),
    SiponCityEntry('来宾', 'Laibin', 109.22, 23.73),
    SiponCityEntry('崇左', 'Chongzuo', 107.36, 22.40),
  ]),
  SiponProvinceEntry('海南省', 'Hainan', [
    SiponCityEntry('海口', 'Haikou', 110.35, 20.02),
    SiponCityEntry('三亚', 'Sanya', 109.51, 18.25),
    SiponCityEntry('三沙', 'Sansha', 112.33, 16.83),
    SiponCityEntry('儋州', 'Danzhou', 109.58, 19.52),
  ]),
  SiponProvinceEntry('重庆市', 'Chongqing', [SiponCityEntry('重庆', 'Chongqing', 106.55, 29.56)]),
  SiponProvinceEntry('四川省', 'Sichuan', [
    SiponCityEntry('成都', 'Chengdu', 104.07, 30.57),
    SiponCityEntry('自贡', 'Zigong', 104.78, 29.35),
    SiponCityEntry('攀枝花', 'Panzhihua', 101.72, 26.58),
    SiponCityEntry('泸州', 'Luzhou', 105.44, 28.87),
    SiponCityEntry('德阳', 'Deyang', 104.40, 31.13),
    SiponCityEntry('绵阳', 'Mianyang', 104.68, 31.47),
    SiponCityEntry('广元', 'Guangyuan', 105.84, 32.44),
    SiponCityEntry('遂宁', 'Suining', 105.59, 30.53),
    SiponCityEntry('内江', 'Neijiang', 105.06, 29.58),
    SiponCityEntry('乐山', 'Leshan', 103.77, 29.55),
    SiponCityEntry('南充', 'Nanchong', 106.11, 30.84),
    SiponCityEntry('眉山', 'Meishan', 103.85, 30.08),
    SiponCityEntry('宜宾', 'Yibin', 104.64, 28.75),
    SiponCityEntry('广安', 'Guang\'an', 106.63, 30.46),
    SiponCityEntry('达州', 'Dazhou', 107.47, 31.21),
    SiponCityEntry('雅安', 'Ya\'an', 103.04, 29.98),
    SiponCityEntry('巴中', 'Bazhong', 106.75, 31.87),
    SiponCityEntry('资阳', 'Ziyang', 104.63, 30.12),
    SiponCityEntry('阿坝', 'Aba', 102.22, 31.90),
    SiponCityEntry('甘孜', 'Garze', 101.96, 30.05),
    SiponCityEntry('凉山', 'Liangshan', 102.26, 27.88),
  ]),
  SiponProvinceEntry('贵州省', 'Guizhou', [
    SiponCityEntry('贵阳', 'Guiyang', 106.63, 26.65),
    SiponCityEntry('六盘水', 'Liupanshui', 104.83, 26.59),
    SiponCityEntry('遵义', 'Zunyi', 106.93, 27.73),
    SiponCityEntry('安顺', 'Anshun', 105.95, 26.25),
    SiponCityEntry('毕节', 'Bijie', 105.29, 27.30),
    SiponCityEntry('铜仁', 'Tongren', 109.19, 27.72),
    SiponCityEntry('黔西南', 'Qianxinan', 104.90, 25.09),
    SiponCityEntry('黔东南', 'Qiandongnan', 107.98, 26.58),
    SiponCityEntry('黔南', 'Qiannan', 107.52, 26.27),
  ]),
  SiponProvinceEntry('云南省', 'Yunnan', [
    SiponCityEntry('昆明', 'Kunming', 102.83, 24.88),
    SiponCityEntry('曲靖', 'Qujing', 103.80, 25.49),
    SiponCityEntry('玉溪', 'Yuxi', 102.55, 24.35),
    SiponCityEntry('保山', 'Baoshan', 99.16, 25.11),
    SiponCityEntry('昭通', 'Zhaotong', 103.72, 27.34),
    SiponCityEntry('丽江', 'Lijiang', 100.23, 26.88),
    SiponCityEntry('普洱', 'Pu\'er', 100.97, 22.78),
    SiponCityEntry('临沧', 'Lincang', 100.09, 23.88),
    SiponCityEntry('楚雄', 'Chuxiong', 101.55, 25.04),
    SiponCityEntry('红河', 'Honghe', 103.38, 23.36),
    SiponCityEntry('文山', 'Wenshan', 104.22, 23.37),
    SiponCityEntry('西双版纳', 'Xishuangbanna', 100.80, 22.01),
    SiponCityEntry('大理', 'Dali', 100.27, 25.61),
    SiponCityEntry('德宏', 'Dehong', 98.59, 24.43),
    SiponCityEntry('怒江', 'Nujiang', 98.85, 25.85),
    SiponCityEntry('迪庆', 'Diqing', 99.71, 27.83),
  ]),
  SiponProvinceEntry('西藏自治区', 'Tibet', [
    SiponCityEntry('拉萨', 'Lhasa', 91.14, 29.97),
    SiponCityEntry('日喀则', 'Shigatse', 88.88, 29.27),
    SiponCityEntry('昌都', 'Qamdo', 97.17, 31.14),
    SiponCityEntry('林芝', 'Nyingchi', 94.36, 29.65),
    SiponCityEntry('山南', 'Shannan', 91.77, 29.22),
    SiponCityEntry('那曲', 'Nagqu', 92.05, 31.48),
    SiponCityEntry('阿里', 'Ngari', 80.10, 32.50),
  ]),
  SiponProvinceEntry('陕西省', 'Shaanxi', [
    SiponCityEntry('西安', 'Xi\'an', 108.94, 34.34),
    SiponCityEntry('铜川', 'Tongchuan', 108.95, 34.90),
    SiponCityEntry('宝鸡', 'Baoji', 107.24, 34.36),
    SiponCityEntry('咸阳', 'Xianyang', 108.71, 34.33),
    SiponCityEntry('渭南', 'Weinan', 109.51, 34.50),
    SiponCityEntry('延安', 'Yan\'an', 109.49, 36.59),
    SiponCityEntry('汉中', 'Hanzhong', 107.02, 33.07),
    SiponCityEntry('榆林', 'Yulin', 109.73, 38.29),
    SiponCityEntry('安康', 'Ankang', 109.03, 32.68),
    SiponCityEntry('商洛', 'Shangluo', 109.94, 33.87),
  ]),
  SiponProvinceEntry('甘肃省', 'Gansu', [
    SiponCityEntry('兰州', 'Lanzhou', 103.83, 36.06),
    SiponCityEntry('嘉峪关', 'Jiayuguan', 98.29, 39.77),
    SiponCityEntry('金昌', 'Jinchang', 102.19, 38.50),
    SiponCityEntry('白银', 'Baiyin', 104.14, 36.55),
    SiponCityEntry('天水', 'Tianshui', 105.72, 34.58),
    SiponCityEntry('武威', 'Wuwei', 102.63, 37.93),
    SiponCityEntry('张掖', 'Zhangye', 100.45, 38.93),
    SiponCityEntry('平凉', 'Pingliang', 106.67, 35.54),
    SiponCityEntry('酒泉', 'Jiuquan', 98.49, 39.73),
    SiponCityEntry('庆阳', 'Qingyang', 107.64, 35.71),
    SiponCityEntry('定西', 'Dingxi', 104.63, 35.58),
    SiponCityEntry('陇南', 'Longnan', 104.92, 33.40),
    SiponCityEntry('临夏', 'Linxia', 103.21, 35.60),
    SiponCityEntry('甘南', 'Gannan', 102.91, 34.98),
  ]),
  SiponProvinceEntry('青海省', 'Qinghai', [
    SiponCityEntry('西宁', 'Xining', 101.78, 36.62),
    SiponCityEntry('海东', 'Haidong', 102.41, 36.47),
    SiponCityEntry('海北', 'Haibei', 100.98, 36.93),
    SiponCityEntry('黄南', 'Huangnan', 102.02, 35.52),
    SiponCityEntry('海南', 'Hainan', 99.98, 36.28),
    SiponCityEntry('果洛', 'Guoluo', 100.24, 34.48),
    SiponCityEntry('玉树', 'Yushu', 97.01, 33.00),
    SiponCityEntry('海西', 'Haixi', 97.37, 37.38),
  ]),
  SiponProvinceEntry('宁夏回族自治区', 'Ningxia', [
    SiponCityEntry('银川', 'Yinchuan', 106.23, 38.49),
    SiponCityEntry('石嘴山', 'Shizuishan', 106.38, 39.01),
    SiponCityEntry('吴忠', 'Wuzhong', 106.20, 37.99),
    SiponCityEntry('固原', 'Guyuan', 106.24, 36.02),
    SiponCityEntry('中卫', 'Zhongwei', 105.19, 37.51),
  ]),
  SiponProvinceEntry('新疆维吾尔自治区', 'Xinjiang', [
    SiponCityEntry('乌鲁木齐', 'Urumqi', 87.62, 43.83),
    SiponCityEntry('克拉玛依', 'Karamay', 84.87, 45.58),
    SiponCityEntry('吐鲁番', 'Turpan', 89.18, 42.95),
    SiponCityEntry('哈密', 'Hami', 93.51, 42.83),
    SiponCityEntry('昌吉', 'Changji', 87.30, 44.01),
    SiponCityEntry('博尔塔拉', 'Bortala', 82.08, 44.91),
    SiponCityEntry('巴音郭楞', 'Bayingolin', 86.15, 41.73),
    SiponCityEntry('阿克苏', 'Aksu', 80.26, 41.17),
    SiponCityEntry('克孜勒苏', 'Kizilsu', 76.17, 39.71),
    SiponCityEntry('喀什', 'Kashgar', 75.99, 39.47),
    SiponCityEntry('和田', 'Hotan', 79.92, 37.11),
    SiponCityEntry('伊犁', 'Ili', 81.32, 43.98),
    SiponCityEntry('塔城', 'Tacheng', 82.98, 46.75),
    SiponCityEntry('阿勒泰', 'Altay', 88.14, 47.85),
  ]),
  SiponProvinceEntry('香港特别行政区', 'Hong Kong', [SiponCityEntry('香港', 'Hong Kong', 114.17, 22.30)]),
  SiponProvinceEntry('澳门特别行政区', 'Macao', [SiponCityEntry('澳门', 'Macao', 113.54, 22.20)]),
  SiponProvinceEntry('台湾省', 'Taiwan', [
    SiponCityEntry('台北', 'Taipei', 121.56, 25.03),
    SiponCityEntry('高雄', 'Kaohsiung', 120.31, 22.62),
    SiponCityEntry('台中', 'Taichung', 120.68, 24.14),
    SiponCityEntry('台南', 'Tainan', 120.20, 22.99),
  ]),
];

/// 在内置表中按城市名查找，兼容“上海 / 上海市 / 上海市辖区”写法。
SiponCityEntry? siponFindCity(String city) {
  final query = city.trim();
  if (query.isEmpty) {
    return null;
  }
  for (final province in siponProvinces) {
    for (final entry in province.cities) {
      if (_cityNameMatches(entry.name, query)) {
        return entry;
      }
    }
  }
  return null;
}

/// 反查城市所属省份，找不到返回 null。
String? siponFindProvinceOfCity(String city) {
  final query = city.trim();
  if (query.isEmpty) {
    return null;
  }
  for (final province in siponProvinces) {
    for (final entry in province.cities) {
      if (_cityNameMatches(entry.name, query)) {
        return province.name;
      }
    }
  }
  return null;
}

/// 反查城市所属省份的英文名，找不到返回 null。
String? siponProvinceEnOfCity(String city) {
  final query = city.trim();
  if (query.isEmpty) {
    return null;
  }
  for (final province in siponProvinces) {
    for (final entry in province.cities) {
      if (_cityNameMatches(entry.name, query)) {
        return province.nameEn;
      }
    }
  }
  return null;
}

/// 取城市英文名，找不到返回原名（用于兜底展示）。
String siponCityEn(String city) => siponFindCity(city)?.nameEn ?? city;

/// 返回传给后端接口的城市名称。
///
/// 城市选择器内部使用简称（例如“广州”），后端按行政区全称筛选
/// （例如“广州市”）。已带行政区后缀的名称保持不变。
String siponApiCityName(String city) {
  final query = city.trim();
  if (query.isEmpty || _hasAdministrativeSuffix(query)) {
    return query;
  }

  final entry = siponFindCity(query);
  if (entry != null &&
      (entry.name.endsWith('州') ||
          entry.name.endsWith('盟') ||
          entry.name.endsWith('地区') ||
          entry.name == '香港' ||
          entry.name == '澳门' ||
          entry.name == '台北' ||
          entry.name == '高雄' ||
          entry.name == '台中' ||
          entry.name == '台南')) {
    return entry.name;
  }
  return '$query市';
}

bool _hasAdministrativeSuffix(String city) =>
    city.endsWith('市') ||
    city.endsWith('州') ||
    city.endsWith('盟') ||
    city.endsWith('地区') ||
    city.endsWith('特别行政区') ||
    city.endsWith('自治区');

/// 取省份英文名，找不到返回原名。
String siponProvinceEn(String province) {
  final query = province.trim();
  for (final entry in siponProvinces) {
    if (entry.name == query) {
      return entry.nameEn;
    }
  }
  return query;
}

bool _cityNameMatches(String shortName, String query) {
  if (query == shortName) {
    return true;
  }
  // “上海市”以“上海”开头；“上海”以查询“上”开头之类不算，只做双向包含且
  // 长度差不超过 3（如“市 / 自治州 / 地区”后缀），避免“南京”命中“南宁”。
  if (query.startsWith(shortName) && query.length - shortName.length <= 3) {
    return true;
  }
  if (shortName.startsWith(query) && shortName.length - query.length <= 3) {
    return true;
  }
  return false;
}
