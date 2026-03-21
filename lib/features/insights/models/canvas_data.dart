import 'dart:convert';

// FEAT-08: Canvas mode structured response model.
// Parsed from the Netlify ai-analyst function canvas response:
// { summary, insights[], charts[{type,title,labels,data,backgroundColor}], actions[] }

class CanvasChart {
  final String type;
  final String title;
  final List<String> labels;
  final List<double> data;
  final List<String> backgroundColor;

  const CanvasChart({
    required this.type,
    required this.title,
    required this.labels,
    required this.data,
    required this.backgroundColor,
  });

  factory CanvasChart.fromJson(Map<String, dynamic> j) => CanvasChart(
        type: j['type'] as String? ?? 'bar',
        title: j['title'] as String? ?? '',
        labels: (j['labels'] as List?)?.cast<String>() ?? [],
        data: (j['data'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            [],
        backgroundColor:
            (j['backgroundColor'] as List?)?.cast<String>() ?? [],
      );
}

class CanvasData {
  final String summary;
  final List<String> insights;
  final List<CanvasChart> charts;
  final List<String> actions;

  const CanvasData({
    required this.summary,
    required this.insights,
    required this.charts,
    required this.actions,
  });

  factory CanvasData.fromJson(Map<String, dynamic> j) => CanvasData(
        summary: j['summary'] as String? ?? '',
        insights: (j['insights'] as List?)?.cast<String>() ?? [],
        charts: (j['charts'] as List?)
                ?.map((c) => CanvasChart.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        actions: (j['actions'] as List?)?.cast<String>() ?? [],
      );

  /// Parse a [CanvasData] from the raw JSON string stored after the
  /// `__CANVAS__:` sentinel in an [AiChatMessage.content].
  static CanvasData? tryParseFromSentinel(String content) {
    const sentinel = '__CANVAS__:';
    final idx = content.indexOf(sentinel);
    if (idx < 0) return null;
    try {
      final raw = content.substring(idx + sentinel.length).trim();
      final decoded = jsonDecode(raw);
      final map = (decoded as Map?)?.cast<String, dynamic>() ?? {};
      return CanvasData.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
