import 'dart:io';

void main() async {
  // 你可以根据需要改回 args[0] 来支持命令行输入
  const String aarPath = '/Users/mcgrady/Downloads/ujusdk_dev/ad_sdk/build/outputs/aar/ad_sdk-release.aar';

  final aarFile = File(aarPath);
  if (!aarFile.existsSync()) {
    print('❌ 错误: 找不到文件: $aarPath');
    return;
  }

  final tempDir = Directory('temp_aar_extract');
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  tempDir.createSync();

  try {
    print('🚀 开始全量扫描: ${aarPath.split('/').last}');
    Process.runSync('unzip', ['-o', aarPath, '-d', tempDir.path]);

    final classesJar = File('${tempDir.path}/classes.jar');
    if (!classesJar.existsSync()) return;

    final jarDir = Directory('${tempDir.path}/jar_content');
    jarDir.createSync();
    Process.runSync('unzip', ['-o', classesJar.path, '-d', jarDir.path]);

    final allFiles = jarDir.listSync(recursive: true).whereType<File>().toList();

    // 用于版本汇总统计
    Map<String, int> kotlinVersionStats = {};
    int totalClassCount = 0;

    // --- [1] Kotlin 类文件分析 ---
    print('\n🔍 [1] Class Metadata (Kotlin mv 数组):');
    for (var file in allFiles) {
      if (!file.path.endsWith('.class')) continue;
      totalClassCount++;

      final result = Process.runSync('javap', ['-v', file.path]);
      final output = result.stdout as String;

      if (output.contains('Lkotlin/Metadata;')) {
        final match = RegExp(r'mv=\[([0-9, ]+)\]|mv=\{([0-9, ]+)\}').firstMatch(output);
        String version = '未知';
        if (match != null) {
          version = (match.group(1) ?? match.group(2) ?? '').replaceAll(' ', '').replaceAll(',', '.');
        }

        // 记录统计
        kotlinVersionStats[version] = (kotlinVersionStats[version] ?? 0) + 1;

        // 只有当版本异常或者样本较少时打印详细信息，防止刷屏
        if (totalClassCount <= 10 || version.startsWith('2.')) {
          print('  - ${file.uri.pathSegments.last.padRight(30)} -> mv={$version}');
        }
      }
    }

    // --- [2] .kotlin_module 智能解析 ---
    print('\n🔍 [2] .kotlin_module 模块描述文件:');
    for (var file in allFiles) {
      if (!file.path.endsWith('.kotlin_module')) continue;
      final bytes = file.readAsBytesSync();
      final version = _parseKotlinModuleVersion(bytes);
      print('  - ${file.uri.pathSegments.last.padRight(30)} -> $version');
    }

    // --- [3] Java 字节码版本 ---
    final firstClass = allFiles.firstWhere((f) => f.path.endsWith('.class'));
    final res = Process.runSync('javap', ['-v', firstClass.path]);
    final major = RegExp(r'major version: (\d+)').firstMatch(res.stdout as String)?.group(1);

    // --- [总结报告] ---
    print('\n📊 --- 分析汇总报告 ---');
    print('📦 总类文件数: $totalClassCount');
    print('🎼 Kotlin 版本分布:');
    kotlinVersionStats.forEach((ver, count) {
      print('   - Kotlin $ver: $count 个类');
    });
    print('☕ Java 编译级别: ${_getJavaVersion(major!)} (Major $major)');
    print('----------------------');

  } finally {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    print('\n✅ 扫描结束');
  }
}

String _parseKotlinModuleVersion(List<int> bytes) {
  if (bytes.length < 12) return "Unknown (too short)";
  List<int> versionComponents = [];
  for (int i = 4; i < bytes.length - 3; i++) {
    if (bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0) {
      int value = bytes[i + 3];
      if (value > 0 && value < 20) { // 过滤掉异常值
        versionComponents.add(value);
      }
      if (versionComponents.length >= 2) break;
    }
  }
  return versionComponents.isNotEmpty ? versionComponents.join('.') : "解析失败";
}

String _getJavaVersion(String major) {
  final Map<String, String> javaVersions = {
    '45': '1.1', '46': '1.2', '47': '1.3', '48': '1.4', '49': '5', '50': '6', '51': '7',
    '52': '8', '53': '9', '54': '10', '55': '11', '56': '12', '57': '13', '58': '14',
    '59': '15', '60': '16', '61': '17', '62': '18', '63': '19', '64': '20', '65': '21',
    '66': '22', '67': '23', '68': '24', '69': '25'
  };
  return 'Java ${javaVersions[major] ?? "Unknown($major)"}';
}