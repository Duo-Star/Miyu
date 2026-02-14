import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'filter_text_controller.dart';

void main() {
  runApp(const MyApp());
}

/// ===== Rule Model =====

class RuleItem {
  final String k;
  final String v;
  RuleItem(this.k, this.v);
}

class Rule {
  final String name;
  final String split;
  final List<RuleItem> items;

  Rule(this.name, this.split, this.items);
}

/// ===== Theme Controller =====

class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;
  Color seed = Colors.blue;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    mode = ThemeMode.values[sp.getInt("themeMode") ?? 0];
    seed = Color(sp.getInt("themeSeed") ?? Colors.blue.value);
    notifyListeners();
  }

  Future<void> setSeed(Color c) async {
    seed = c;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt("themeSeed", c.value);
  }

  Future<void> setMode(ThemeMode m) async {
    mode = m;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt("themeMode", m.index);
  }
}

final themeCtrl = ThemeController();

/// ===== Crypto =====

class CryptoEngine {
  static String encrypt(String text, Rule rule) {
    final codes = text.runes;
    String result = "";

    for (final c in codes) {
      result += "$c${rule.split}";
    }

    for (final item in rule.items) {
      result = result.replaceAll(item.k, item.v);
    }

    return result;
  }

  static String decrypt(String text, Rule rule) {
    if (!text.contains(rule.split)) return "规则不匹配";

    final parts = text.split(rule.split);
    String result = "";

    for (final p in parts) {
      if (p.isEmpty) continue;

      String d = p;
      for (final item in rule.items) {
        d = d.replaceAll(item.v, item.k);
      }

      final cp = int.tryParse(d);
      if (cp == null) return "非法字符";

      result += String.fromCharCode(cp);
    }

    return result;
  }
}

/// ===== Clipboard (Web 优化) =====

class Clip {
  static Future<void> copy(String text) async {
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: text));
    } else {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  static Future<String> paste() async {
    final d = await Clipboard.getData("text/plain");
    return d?.text ?? "";
  }
}

/// ===== App =====

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    themeCtrl.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeCtrl,
      builder: (_, __) {
        return MaterialApp(
          themeMode: themeCtrl.mode,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: themeCtrl.seed,
            fontFamily: "MyFont",
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: themeCtrl.seed,
            fontFamily: "MyFont",
            brightness: Brightness.dark,
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

/// ===== Home =====

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Rule> rules = [];
  Rule? currentRule;

  late FilterTextController input;
  late FilterTextController output;


  bool encryptMode = true;

  @override
  void initState() {
    super.initState();

    input = FilterTextController(
      hiddenRunes: hiddenChars,
    );

    output = FilterTextController(
      hiddenRunes: hiddenChars,
    );

    loadRules();
    input.addListener(process);
  }


  Future<void> loadRules() async {
    final str = await rootBundle.loadString("assets/rules.json");
    final data = jsonDecode(str);

    rules = (data as List).map((e) {
      return Rule(
        e["name"],
        e["split"],
        (e["items"] as List)
            .map((i) => RuleItem(i["k"], i["v"]))
            .toList(),
      );
    }).toList();

    final sp = await SharedPreferences.getInstance();
    final last = sp.getString("ruleName");

    setState(() {
      currentRule =
          rules.firstWhere((e) => e.name == last, orElse: () => rules.first);
    });
  }

  Future<void> saveRule() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString("ruleName", currentRule?.name ?? "");
  }

  void process() {
    if (currentRule == null) return;

    if (encryptMode) {
      output.text = CryptoEngine.encrypt(input.text, currentRule!);
    } else {
      output.text = CryptoEngine.decrypt(input.text, currentRule!);
    }
  }

  /// ===== UI =====

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text("密语"),
        actions: [
          buildRuleSelector(),
          PopupMenuButton(
            itemBuilder: (_) => [
              const PopupMenuItem(value: "theme", child: Text("主题")),
              const PopupMenuItem(value: "about", child: Text("关于")),
            ],
            onSelected: (v) {
              if (v == "theme") showThemeDialog();
              if (v == "about") showAbout();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: wide ? buildWide() : buildPortrait(),
      ),
    );
  }

  Widget buildPortrait() {
    return Column(
      children: [
        Expanded(child: buildInput()),
        const SizedBox(height: 12),
        buildActions(),
        const SizedBox(height: 12),
        Expanded(child: buildOutput()),
      ],
    );
  }

  Widget buildWide() {
    return Column(
      children: [
        buildActions(),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            children: [
              Expanded(child: buildInput()),
              const SizedBox(width: 20),
              Expanded(child: buildOutput()),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildRuleSelector() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<Rule>(
        value: currentRule,
        items: rules
            .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
            .toList(),
        onChanged: (r) {
          setState(() => currentRule = r);
          saveRule();
          process();
        },
      ),
    );
  }

  Widget buildInput() {
    return TextField(
      controller: input,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontFamily: "Code"),
      decoration: const InputDecoration(
        hintText: "输入",
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget buildOutput() {
    return TextField(
      controller: output,
      readOnly: true,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontFamily: "Code"),
      decoration: const InputDecoration(
        hintText: "输出",
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget buildActions() {
    return Row(
      children: [
        TextButton(
          onPressed: () async {
            input.text = await Clip.paste();
          },
          child: const Text("粘贴"),
        ),
        const Spacer(),
        Row(
          children: [
            Radio(
              value: true,
              groupValue: encryptMode,
              onChanged: (_) {
                setState(() => encryptMode = true);
                process();
              },
            ),
            const Text("加密"),
            Radio(
              value: false,
              groupValue: encryptMode,
              onChanged: (_) {
                setState(() => encryptMode = false);
                process();
              },
            ),
            const Text("解密"),
          ],
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Clip.copy(output.text),
          child: const Text("复制"),
        ),
      ],
    );
  }

  /// ===== Theme Dialog =====

  void showThemeDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("主题"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              children: [
                themeColor(Colors.blue),
                themeColor(Colors.green),
                themeColor(Colors.red),
                themeColor(Colors.purple),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () => themeCtrl.setMode(ThemeMode.light),
                  child: const Text("日间"),
                ),
                TextButton(
                  onPressed: () => themeCtrl.setMode(ThemeMode.dark),
                  child: const Text("夜间"),
                ),
                TextButton(
                  onPressed: () => themeCtrl.setMode(ThemeMode.system),
                  child: const Text("系统"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget themeColor(Color c) {
    return GestureDetector(
      onTap: () => themeCtrl.setSeed(c),
      child: CircleAvatar(backgroundColor: c),
    );
  }

  /// ===== About =====

  void showAbout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("关于"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("密语 0.1.0"),
            const Text("用于整活的文本加密解密系统"),
            const SizedBox(height: 12),
            InkWell(
              child: const Text(
                "https://www.mduo.cloud/",
                style: TextStyle(
                  decoration: TextDecoration.underline,
                  color: Colors.blue,
                ),
              ),
              onTap: () async {
                await launchUrl(Uri.parse("https://www.mduo.cloud/"));
              },
            ),
          ],
        ),
      ),
    );
  }
}
