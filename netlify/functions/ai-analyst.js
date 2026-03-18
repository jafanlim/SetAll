exports.handler = async (event) => {
  const headers = { 
    'Access-Control-Allow-Origin': '*', 
    'Access-Control-Allow-Headers': 'Content-Type, Authorization', 
    'Access-Control-Allow-Methods': 'POST, OPTIONS' 
  };
  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers, body: '' };
  try {
    const { query } = JSON.parse(event.body);
    const apiKey = process.env.GEMINI_API_KEY;
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-09-2025:generateContent?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [{ text: query }] }],
        systemInstruction: { parts: [{ text: "You are SetAll AI, a direct, witty, and brilliant financial strategist. Your response MUST be a valid JSON object with a 'summary' key. The 'summary' field is your expressive voice — be human, give advice, be direct. For casual chat (hello, who are you, tell me a joke), just return {\"summary\": \"your witty response\"}. For financial analysis, also include 'insights' (string array) and optionally 'charts' and 'actions'. NEVER return empty JSON {}. NEVER wrap output in markdown code fences. Output raw JSON only." }] },
        generationConfig: { temperature: 0.7 }
      })
    });
    const result = await response.json();
    const actual = (result.candidates?.[0]?.content?.parts ?? []).find(p => p.text && !p.thought);
    const rawText = actual?.text?.trim() || '';
    // Strip markdown code fences
    const cleaned = rawText.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/```\s*$/g, '').trim();
    // If output doesn't start with { it's plain prose — wrap it as summary
    const finalBody = cleaned.startsWith('{') ? cleaned : JSON.stringify({ summary: cleaned });
    let parsed = {};
    try {
      parsed = JSON.parse(finalBody);
    } catch (_) {
      parsed = { summary: cleaned };
    }
    if (!parsed.summary) parsed.summary = cleaned || 'Ask me anything about your finances!';
    return { statusCode: 200, headers, body: JSON.stringify({ report: JSON.stringify(parsed) }) };
  } catch (error) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: error.message }) };
  }
};
