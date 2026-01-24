
import { GoogleGenAI, Type } from "@google/genai";
import { BrowserApp } from "../types";

export const suggestBrowser = async (
  url: string,
  sourceApp: string,
  browsers: BrowserApp[]
): Promise<{ browserId: string; reasoning: string }> => {
  try {
    const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });
    const browserList = browsers.map(b => `- ${b.name} (ID: ${b.id}, Type: ${b.type})`).join('\n');

    const response = await ai.models.generateContent({
      model: "gemini-3-flash-preview",
      contents: `
        Context: A user clicked a link in a macOS app.
        URL: "${url}"
        Source Application: "${sourceApp}"
        Available Browsers:
        ${browserList}

        Task: Recommend which browser should open this link. 
        General heuristics:
        - Work apps (Jira, Figma, GitHub, Docs) -> Chrome or Arc
        - Personal/Light reading (News, Social Media, Blogs) -> Safari
        - Privacy-sensitive or Dev tools (Localhost) -> Firefox or Chrome
        
        Return the recommendation in JSON format with "browserId" and "reasoning" (max 15 words).
      `,
      config: {
        responseMimeType: "application/json",
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            browserId: { type: Type.STRING },
            reasoning: { type: Type.STRING }
          },
          required: ["browserId", "reasoning"]
        }
      }
    });

    const result = JSON.parse(response.text || '{}');
    // Ensure the ID exists in our list, otherwise fallback
    const exists = browsers.find(b => b.id === result.browserId);
    return exists ? result : { browserId: browsers[0].id, reasoning: "Falling back to default browser." };
  } catch (error) {
    console.error("Gemini AI error:", error);
    return { browserId: browsers[0].id, reasoning: "AI suggestion currently unavailable." };
  }
};
