// 深色模式验收用的固定色扫描器。
//
// 方案第 9 节要求「UI 固定色扫描中的残留项逐项登记用途」，本脚本给出可重复的扫描结果，
// 便于逐项核对每个残留常量是否已在代码注释里登记为内容固有色。
//
// 用法（仓库根目录）：
//   dart run tool/scan_hardcoded_colors.dart            # 扫描 lib/，跳过主题层
//   dart run tool/scan_hardcoded_colors.dart --all      # 连同主题层一起扫描
//   dart run tool/scan_hardcoded_colors.dart --feature  # 只看 lib/features
import 'dart:io';

/// 固定色字面量：`Colors.white`、`Colors.black54`、`Color(0xFF...)`。
///
/// `Colors.transparent` 不纳入统计：它在两种外观下语义一致，不是浅色残留。
final RegExp _literal = RegExp(
  r'Colors\.(?:white|black|grey|blueGrey)\d*(?![A-Za-z])'
  r'|Color\(0x[0-9A-Fa-f]{8}\)',
);

/// 主题层自身必须持有色值，默认不纳入「残留」统计。
const List<String> _themeLayer = <String>['lib/app/theme/'];

/// 已登记为内容固有色 / 沉浸式底色的残留常量。
///
/// 键是文件相对路径，值是该文件里允许保留的色值字面量集合；出现集合之外的固定色时
/// 说明又新增了未登记的颜色，需要在方案文档的残留清单里补登用途。
final Map<String, Set<String>> _registeredResiduals = <String, Set<String>>{};

void main(List<String> args) {
  final includeTheme = args.contains('--all');
  final featuresOnly = args.contains('--feature');

  final files =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('.g.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  var totalResiduals = 0;
  var totalUnregistered = 0;

  for (final file in files) {
    final path = file.path.replaceAll(r'\', '/');
    if (featuresOnly && !path.startsWith('lib/features/')) continue;
    if (!includeTheme && _themeLayer.any(path.startsWith)) continue;

    final registered = _registeredResiduals[path] ?? const <String>{};
    final hits = <(int, String)>[];
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.trimLeft().startsWith('//')) continue;
      for (final match in _literal.allMatches(line)) {
        hits.add((index + 1, match.group(0)!));
      }
    }
    if (hits.isEmpty) continue;

    final unregistered = hits
        .where((hit) => !registered.contains(hit.$2))
        .toList();
    totalResiduals += hits.length;
    totalUnregistered += unregistered.length;

    stdout.writeln('$path  (${hits.length} 处)');
    for (final hit in hits) {
      final mark = registered.contains(hit.$2) ? '已登记' : '待登记';
      stdout.writeln('  ${hit.$1}: ${hit.$2}  [$mark]');
    }
  }

  stdout.writeln('');
  stdout.writeln('合计残留固定色 $totalResiduals 处，其中未登记 $totalUnregistered 处。');
  if (totalUnregistered > 0) {
    stdout.writeln('请在 docs/dark-mode-adaptation-plan.md 的残留清单里补齐用途说明。');
  }
}
