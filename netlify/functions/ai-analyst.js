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
        systemInstruction: { parts: [{ text: "You are SetAll AI, a financial expert. You MUST return ONLY valid JSON. Every response MUST include a 'summary' field (string). If the user is just chatting (e.g. 'hello', 'thanks'), put your friendly greeting or reply in the 'summary' field and omit other fields. If analyzing financial data, also include 'insights' (array of strings) and optionally 'chartData' (Chart.js config object) and 'actions' (array of action strings). Never return empty JSON. Never include thought tokens or markdown." }] },
        generationConfig: { responseMimeType: "application/json", temperature: 0.5 }
      })
    });
    const result = await response.json();
    const actual = (result.candidates?.[0]?.content?.parts ?? []).find(p => p.text && !p.thought);
    const rawText = actual?.text?.trim() || '{}';
    // Ensure the parsed JSON always has a summary field
    let parsed = {};
    try { parsed = JSON.parse(rawText); } catch (_) { parsed = { summary: rawText }; }
    if (!parsed.summary) parsed.summary = 'Here is my analysis based on your financial data.';
    return { statusCode: 200, headers, body: JSON.stringify({ report: JSON.stringify(parsed) }) };
  } catch (error) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: error.message }) };
  }
};
