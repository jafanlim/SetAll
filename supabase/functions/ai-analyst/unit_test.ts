/**
 * Unit tests for the ai-analyst Edge Function logic.
 *
 * Tests the response parsing, JSON validation, Chart.js config sanitisation,
 * and text-fallback behaviour without hitting the real Gemini API.
 *
 * Run:  deno test supabase/functions/ai-analyst/unit_test.ts --allow-env
 */

import {
  assertEquals,
  assertExists,
} from 'https://deno.land/std@0.168.0/testing/asserts.ts'

// ─────────────────────────────────────────────────────────────────────────────
// Inline copies of validation logic from index.ts (avoids importing the
// serve()-wrapped module which auto-starts the HTTP server).
// ─────────────────────────────────────────────────────────────────────────────

const VALID_CHART_TYPES = new Set(['bar', 'line', 'pie', 'doughnut'])
const VALID_ACTIONS = new Set([
  'ADD_TREND',
  'ADD_DONUT',
  'REFRESH',
  'SIGNOUT',
  'PORTAL',
])

interface StructuredResponse {
  summary: string
  insights: string[]
  chartData: unknown
  actions: string[]
}

/** Mirrors the parse logic in index.ts lines 163-184 */
function parseGeminiResponse(rawText: string): {
  reply: string
  structured: StructuredResponse | null
} {
  // Strip markdown fences
  const cleaned = rawText
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/i, '')
    .trim()

  let structured: StructuredResponse | null = null
  let reply = cleaned || 'No response from Gemini.'

  try {
    const parsed = JSON.parse(cleaned)
    const summary =
      typeof parsed.summary === 'string' ? parsed.summary : reply
    const insights = Array.isArray(parsed.insights)
      ? parsed.insights.filter((i: unknown) => typeof i === 'string')
      : []
    const actions = Array.isArray(parsed.actions)
      ? parsed.actions.filter(
          (a: unknown) =>
            typeof a === 'string' && VALID_ACTIONS.has(a as string)
        )
      : []

    let chartData = null
    if (parsed.chartData && typeof parsed.chartData === 'object') {
      const ct = parsed.chartData
      if (
        VALID_CHART_TYPES.has(ct.type) &&
        ct.data &&
        typeof ct.data === 'object'
      ) {
        // Normalise pie/doughnut datasets so values sum to 100.
        // Prevents Gemini hallucinating percentages that overflow the arc.
        if ((ct.type === 'pie' || ct.type === 'doughnut') &&
            Array.isArray(ct.data.datasets) &&
            ct.data.datasets.length > 0) {
          const dataset = ct.data.datasets[0]
          if (Array.isArray(dataset?.data)) {
            const total = (dataset.data as number[]).reduce((s: number, v: number) => s + (Number(v) || 0), 0)
            if (total > 0 && Math.abs(total - 100) > 0.5) {
              dataset.data = (dataset.data as number[]).map((v: number) =>
                parseFloat(((Number(v) / total) * 100).toFixed(2))
              )
            }
          }
        }
        chartData = ct
      }
    }

    structured = { summary, insights, chartData, actions }
    reply = summary
  } catch {
    // JSON parse failed — plain text fallback
  }

  return { reply, structured }
}

/** Mirrors buildSystemPrompt from index.ts */
function buildSystemPrompt(ctx: {
  totalSpending: number
  dailyBurn: number
  totalIncome: number
  net: number
  topCategories: string
  recentRows: string
}): string {
  return `You are the SetAll Neural Engine — a concise, sharp financial AI assistant embedded in the SetAll personal finance dashboard.

The user's financial snapshot (last 90 days of their personal wallet):
- Total spending: $${ctx.totalSpending.toFixed(2)}
- Daily burn rate: $${ctx.dailyBurn.toFixed(2)}/day
- Top categories: ${ctx.topCategories || 'none yet'}
- Total income logged: $${ctx.totalIncome.toFixed(2)}
- Net: $${ctx.net.toFixed(2)}

Recent transactions (newest last):
${ctx.recentRows || 'No transactions loaded yet.'}`
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

Deno.test('Valid structured JSON is parsed correctly', () => {
  const raw = JSON.stringify({
    summary: 'You spent $120 on food this month.',
    insights: ['Reduce dining out', 'Set a grocery budget'],
    chartData: {
      type: 'bar',
      data: {
        labels: ['Jan', 'Feb', 'Mar'],
        datasets: [{ label: 'Spending', data: [100, 120, 80] }],
      },
      options: { responsive: true },
    },
    actions: ['ADD_TREND'],
  })

  const { reply, structured } = parseGeminiResponse(raw)

  assertEquals(reply, 'You spent $120 on food this month.')
  assertExists(structured)
  assertEquals(structured!.insights.length, 2)
  assertExists(structured!.chartData)
  assertEquals(structured!.actions, ['ADD_TREND'])
})

Deno.test('chartData with invalid type is rejected', () => {
  const raw = JSON.stringify({
    summary: 'Here is your chart.',
    insights: [],
    chartData: {
      type: 'radar', // not in VALID_CHART_TYPES
      data: { labels: ['A'], datasets: [] },
    },
    actions: [],
  })

  const { structured } = parseGeminiResponse(raw)

  assertExists(structured)
  assertEquals(structured!.chartData, null, 'Invalid chart type must be rejected')
})

Deno.test('chartData without data object is rejected', () => {
  const raw = JSON.stringify({
    summary: 'No data chart.',
    insights: [],
    chartData: {
      type: 'bar',
      // missing 'data' key
    },
    actions: [],
  })

  const { structured } = parseGeminiResponse(raw)

  assertExists(structured)
  assertEquals(structured!.chartData, null, 'chartData without data object must be null')
})

Deno.test('null chartData is preserved', () => {
  const raw = JSON.stringify({
    summary: 'No chart needed.',
    insights: ['Save more'],
    chartData: null,
    actions: [],
  })

  const { structured } = parseGeminiResponse(raw)

  assertExists(structured)
  assertEquals(structured!.chartData, null)
  assertEquals(structured!.insights, ['Save more'])
})

Deno.test('Invalid actions are filtered out', () => {
  const raw = JSON.stringify({
    summary: 'Action test.',
    insights: [],
    chartData: null,
    actions: ['ADD_TREND', 'HACK_SERVER', 'REFRESH', 'DROP_TABLE'],
  })

  const { structured } = parseGeminiResponse(raw)

  assertExists(structured)
  assertEquals(structured!.actions, ['ADD_TREND', 'REFRESH'],
    'Only whitelisted actions should survive')
})

Deno.test('Non-string insights are filtered out', () => {
  const raw = JSON.stringify({
    summary: 'Insight filter test.',
    insights: ['Valid insight', 42, null, { nested: true }, 'Another valid'],
    chartData: null,
    actions: [],
  })

  const { structured } = parseGeminiResponse(raw)

  assertExists(structured)
  assertEquals(structured!.insights, ['Valid insight', 'Another valid'])
})

Deno.test('Text fallback when Gemini returns non-JSON', () => {
  const raw = 'I apologize, I cannot process your request right now.'

  const { reply, structured } = parseGeminiResponse(raw)

  assertEquals(structured, null, 'Non-JSON must result in null structured')
  assertEquals(reply, raw, 'Raw text should be used as reply fallback')
})

Deno.test('Text fallback when Gemini returns empty string', () => {
  const { reply, structured } = parseGeminiResponse('')

  assertEquals(structured, null)
  assertEquals(reply, 'No response from Gemini.')
})

Deno.test('Markdown-fenced JSON is cleaned and parsed', () => {
  const json = {
    summary: 'Fenced response.',
    insights: [],
    chartData: null,
    actions: [],
  }
  const raw = '```json\n' + JSON.stringify(json) + '\n```'

  const { reply, structured } = parseGeminiResponse(raw)

  assertEquals(reply, 'Fenced response.')
  assertExists(structured)
})

Deno.test('Partial JSON (missing summary) uses raw text as fallback summary', () => {
  const raw = JSON.stringify({
    // no summary key
    insights: ['One insight'],
    chartData: null,
    actions: [],
  })

  const { reply, structured } = parseGeminiResponse(raw)

  assertExists(structured)
  // When summary is missing, the parser falls back to the raw JSON string as reply
  assertEquals(reply, raw)
})

Deno.test('buildSystemPrompt includes financial context', () => {
  const prompt = buildSystemPrompt({
    totalSpending: 1500.5,
    dailyBurn: 16.67,
    totalIncome: 3000.0,
    net: 1499.5,
    topCategories: 'Food: $500, Rent: $1000',
    recentRows: '2026-01-01 | Food | expense | $50.00',
  })

  assertEquals(prompt.includes('$1500.50'), true, 'Must include total spending')
  assertEquals(prompt.includes('$16.67'), true, 'Must include daily burn')
  assertEquals(prompt.includes('Food: $500, Rent: $1000'), true, 'Must include categories')
  assertEquals(prompt.includes('$3000.00'), true, 'Must include total income')
  assertEquals(prompt.includes('$50.00'), true, 'Must include recent transaction')
})

Deno.test('buildSystemPrompt handles empty context gracefully', () => {
  const prompt = buildSystemPrompt({
    totalSpending: 0,
    dailyBurn: 0,
    totalIncome: 0,
    net: 0,
    topCategories: '',
    recentRows: '',
  })

  assertEquals(prompt.includes('none yet'), true, 'Empty categories must show "none yet"')
  assertEquals(prompt.includes('No transactions loaded yet.'), true, 'Empty rows must show fallback')
})

Deno.test('doughnut chart type is accepted', () => {
  const raw = JSON.stringify({
    summary: 'Donut chart.',
    insights: [],
    chartData: {
      type: 'doughnut',
      data: { labels: ['A', 'B'], datasets: [{ data: [60, 40] }] },
    },
    actions: ['ADD_DONUT'],
  })

  const { structured } = parseGeminiResponse(raw)

  assertExists(structured)
  assertExists(structured!.chartData, 'doughnut type must be accepted')
  assertEquals(structured!.actions, ['ADD_DONUT'])
})

// ─────────────────────────────────────────────────────────────────────────────
// Mathematical correctness: pie/doughnut normalization
// Gap identified in TASK 0 pre-flight analysis.
// ─────────────────────────────────────────────────────────────────────────────

Deno.test('pie chart with values summing to 110% is normalised to 100%', () => {
  // Gemini hallucination: [45, 40, 25] = 110 total — overflows SVG arc
  const raw = JSON.stringify({
    summary: 'Category breakdown.',
    insights: [],
    chartData: {
      type: 'pie',
      data: {
        labels: ['Food', 'Rent', 'Travel'],
        datasets: [{ data: [45, 40, 25] }],
      },
    },
    actions: [],
  })

  const { structured } = parseGeminiResponse(raw)

  assertExists(structured)
  assertExists(structured!.chartData)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const dataset = (structured!.chartData as any).data.datasets[0]
  const sum = dataset.data.reduce((s: number, v: number) => s + v, 0)
  assertEquals(
    Math.abs(sum - 100) < 0.5,
    true,
    `Normalised pie values must sum to 100, got ${sum}`
  )
})

Deno.test('doughnut chart with values summing to 150% is normalised to 100%', () => {
  const raw = JSON.stringify({
    summary: 'Spending split.',
    insights: [],
    chartData: {
      type: 'doughnut',
      data: {
        labels: ['A', 'B', 'C'],
        datasets: [{ data: [60, 50, 40] }],
      },
    },
    actions: [],
  })

  const { structured } = parseGeminiResponse(raw)

  assertExists(structured)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const dataset = (structured!.chartData as any).data.datasets[0]
  const sum = dataset.data.reduce((s: number, v: number) => s + v, 0)
  assertEquals(
    Math.abs(sum - 100) < 0.5,
    true,
    `Normalised doughnut values must sum to 100, got ${sum}`
  )
  // Ratios must be preserved: 60:50:40 → 40:33.33:26.67
  assertEquals(dataset.data[0] > dataset.data[1], true, 'Relative order must be preserved')
  assertEquals(dataset.data[1] > dataset.data[2], true, 'Relative order must be preserved')
})

Deno.test('pie chart with already-correct values (sum=100) is NOT altered', () => {
  const raw = JSON.stringify({
    summary: 'Correct pie.',
    insights: [],
    chartData: {
      type: 'pie',
      data: {
        labels: ['A', 'B', 'C'],
        datasets: [{ data: [50, 30, 20] }],
      },
    },
    actions: [],
  })

  const { structured } = parseGeminiResponse(raw)

  assertExists(structured)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const dataset = (structured!.chartData as any).data.datasets[0]
  assertEquals(dataset.data, [50, 30, 20],
    'Values already summing to 100 must not be altered')
})

Deno.test('bar chart with values summing to 110% is NOT normalised (only pie/doughnut)', () => {
  // Bar charts represent absolute values — normalisation must NOT be applied
  const raw = JSON.stringify({
    summary: 'Monthly bar.',
    insights: [],
    chartData: {
      type: 'bar',
      data: {
        labels: ['Jan', 'Feb', 'Mar'],
        datasets: [{ data: [45, 40, 25] }],
      },
    },
    actions: [],
  })

  const { structured } = parseGeminiResponse(raw)

  assertExists(structured)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const dataset = (structured!.chartData as any).data.datasets[0]
  assertEquals(dataset.data, [45, 40, 25],
    'Bar chart values must be preserved as-is — no normalisation')
})
