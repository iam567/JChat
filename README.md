# 💬 Chat Translator

A bilingual chat translation tool powered by AI, designed for real-time conversation translation with tone-aware reply suggestions.

## Features

- 🎭 **6 tone styles**: Formal, Normal, Friend, Funny, Flirty, Arrogant
- 📥 **Translate incoming**: Understand what the other person said
- 📤 **Reply suggestions**: Get 3 different phrasing options, one-click copy
- 🌍 **Multi-language**: Japanese, English, Korean, French, Spanish, Thai
- 🤖 **Multi-AI support**: Claude / OpenAI / Gemini API
- 💾 **Scene management**: Save different chat contexts with history

## Demo

Live demo: [http://c.areu.pro](http://c.areu.pro)

## Quick Start

### Requirements

```bash
pip install flask requests
```

### Run

```bash
python app.py
```

Open `http://localhost:8090` in your browser.

### Configure API Key

Go to ⚙️ Settings and enter your API key:

- **Claude**: Get from [console.anthropic.com](https://console.anthropic.com)
- **OpenAI**: Get from [platform.openai.com](https://platform.openai.com)
- **Gemini**: Get from [aistudio.google.com](https://aistudio.google.com)

## How to Use

1. **New Scene**: Tap `+` → Enter the person's name, language, and your preferred tone
2. **Translate incoming**: Tap `📥 对方说了` → Paste what they said → Get translation
3. **Reply**: Tap `📤 我要回复` → Type your idea in Chinese → Get 3 Japanese reply options → Tap to copy

## Project Structure

```
├── app.py              # Flask backend
├── templates/
│   └── index.html      # Frontend (single-page app)
├── data.json           # Runtime data (auto-created, NOT committed)
└── README.md
```

## Environment

Data is stored in `data.json` at runtime. This file is in `.gitignore` and should never be committed (contains API keys).

## License

MIT
