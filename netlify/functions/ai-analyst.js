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
        systemInstruction: { parts: [{ text: "You are SetAll AI. Return ONLY structured JSON for financial insights. Filter out thought tokens." }] },
        generationConfig: { responseMimeType: "application/json", temperature: 0.4 }
      })
    });
    const result = await response.json();
    const actual = (result.candidates?.[0]?.content?.parts ?? []).find(p => p.text && !p.thought);
    return { statusCode: 200, headers, body: JSON.stringify({ report: actual?.text?.trim() || "{}" }) };
  } catch (error) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: error.message }) };
  }
};
