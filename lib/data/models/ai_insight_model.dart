// FEAT-19: Model for AI weekly/monthly/on_demand insights stored in ai_insights table.
class AiInsightModel {
  const AiInsightModel({
    required this.id,
    required this.userId,
    required this.analysisType,
    required this.periodStart,
    required this.periodEnd,
    required this.summary,
    this.topCategory,
    this.netChange,
    this.incomeTotal,
    this.expenseTotal,
    this.createdAt,
  });

  final String  id;
  final String  userId;
  final String  analysisType;
  final String  periodStart;
  final String  periodEnd;
  final String  summary;
  final String? topCategory;
  final double? netChange;
  final double? incomeTotal;
  final double? expenseTotal;
  final String? createdAt;

  factory AiInsightModel.fromMap(Map<String, dynamic> m) => AiInsightModel(
    id:           m['id']            as String,
    userId:       m['user_id']       as String,
    analysisType: m['analysis_type'] as String,
    periodStart:  m['period_start']  as String,
    periodEnd:    m['period_end']    as String,
    summary:      m['summary']       as String,
    topCategory:  m['top_category']  as String?,
    netChange:    (m['net_change']   as num?)?.toDouble(),
    incomeTotal:  (m['income_total'] as num?)?.toDouble(),
    expenseTotal: (m['expense_total'] as num?)?.toDouble(),
    createdAt:    m['created_at']    as String?,
  );

  Map<String, dynamic> toMap() => {
    'id':            id,
    'user_id':       userId,
    'analysis_type': analysisType,
    'period_start':  periodStart,
    'period_end':    periodEnd,
    'summary':       summary,
    'top_category':  topCategory,
    'net_change':    netChange,
    'income_total':  incomeTotal,
    'expense_total': expenseTotal,
    'created_at':    createdAt,
  };
}
