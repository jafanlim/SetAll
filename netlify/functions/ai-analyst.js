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
        systemInstruction: { parts: [{ text: "You are SetAll AI, a brilliant financial strategist and witty analyst. You have a Dual Mission:\n\nMISSION A — THE VOICE: The 'summary' field is YOUR voice. Be expressive, helpful, and direct. Explain the 'why' behind the numbers like a trusted CFO. If the user chats casually (hello, thanks, who are you), respond like a sharp, friendly human analyst — warm but not sycophantic.\n\nMISSION B — THE DATA: The 'insights', 'charts', and 'actions' fields are your precision JSON engine. Keep them structured and factual.\n\nYou MUST always return a single valid JSON object. Structure:\n{\"summary\": \"Your voice here — always present, always substantive\", \"insights\": [\"string\", ...], \"charts\": [], \"actions\": []}\n\nRules: The 'summary' field is REQUIRED in every response. Never return empty JSON. Never wrap the output in markdown code fences. Output raw JSON only." }] },
        generationConfig: { temperature: 0.7 }
      })
    });
    const result = await response.json();
    const actual = (result.candidates?.[0]?.content?.parts ?? []).find(p => p.text && !p.thought);
    const rawText = actual?.text?.trim() || '';
    // Strip markdown code fences that some model versions emit
    const cleaned = rawText.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/```\s*$/g, '').trim();
    let parsed = {};
    try {
      parsed = JSON.parse(cleaned || '{}');
    } catch (_) {
      // JSON parse failed — treat the whole response as the summary (raw fallback)
      parsed = { summary: cleaned || 'I encountered an issue formulating a response. Please try again.' };
    }
    // Final guarantee: summary must never be empty or a generic placeholder
    if (!parsed.summary || parsed.summary === '{}') {
      parsed.summary = cleaned || 'Ready to analyse your finances — ask me anything!';
    }
    return { statusCode: 200, headers, body: JSON.stringify({ report: JSON.stringify(parsed) }) };
  } catch (error) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: error.message }) };
  }
};
