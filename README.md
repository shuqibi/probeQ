<p align="center">
  <img src="probeQ/Assets.xcassets/AppIcon.appiconset/prQ-256.png" width="128" alt="probeQ Icon" />
</p>

# probeQ

> Built primarily through vibe coding 🎵

Probing the unknown with conversational AI power.

A lightweight macOS menu bar utility that lets you grab text from anywhere on your screen and process it with Universal AI Models (Gemini, DeepSeek, OpenAI, Groq, Kimi, and more) — translate, polish, search, or just chat.

## Features

- **OCR Capture** — Select any region on screen to extract text (supports English & Chinese)
- **Text Selection** — Highlight text in any app, press a shortcut, and send it directly to Gemini
- **Global Shortcuts** — Customizable keybindings that work from any application
- **Chat Interface** — Continue the conversation with follow-up questions
- **Universal AI Models** — Full support for Google Gemini, DeepSeek, OpenAI, Moonshot (Kimi), Groq, Grok (xAI), Zhipu (GLM), Qwen, and Custom OpenAI API Endpoints! Model lists are automatically fetched live.
- **History** — Configurable session history (0 / 20 / 50 chats)

## Demo

### 🔎 <mark> OCR Capture </mark>
<img src="gif_demo/ocr_demo.gif" width="70%" alt="OCR Demo" />

### 🪄 <mark> Text Selection </mark>
<img src="gif_demo/text_select_demo.gif" width="70%" alt="Text Selection Demo" />

## Setup

1. Get an API Key from your chosen provider (e.g. [DeepSeek](https://platform.deepseek.com), [Gemini](https://aistudio.google.com/apikey), or [OpenAI](https://platform.openai.com))
2. Download the latest release or build from source
3. Open the app → click the menu bar icon → Settings → paste your API key → Save
4. Grant **Accessibility** permission when prompted (required for global shortcuts)

> ⚠️ **First launch:** macOS may block the app with *"Apple could not verify..."*. Click below for details.

<details>
<summary><strong>Why does this happen & how to fix it?</strong></summary>

<br>

macOS **Gatekeeper** blocks any app that isn't signed with an Apple Developer certificate ($99/year). Since probeQ is an open-source project distributed outside the App Store, it doesn't carry that signature — so macOS treats it as "unverified" by default. **This does not mean the app is dangerous.** You can review the full source code in this repo.

**To open probeQ:**

1. **Right-click** (or Control+click) on `probeQ.app`
2. Click **"Open"** from the context menu
3. Click **"Open"** again in the confirmation dialog

You only need to do this **once**. After that, macOS remembers your choice and the app will launch normally every time.

**Alternative:** Go to **System Settings → Privacy & Security**, scroll down, and click **"Open Anyway"** next to the probeQ blocked message.

</details>

## Default Shortcuts

| Action    | Shortcut   |
|-----------|------------|
| OCR       | `⌃⌥O`     |
| Translate | `⌃⌥T`     |
| Polish    | `⌃⌥P`     |
| Search    | `⌃⌥S`     |

All shortcuts are fully customizable in Settings → Shortcuts.

## Requirements

- macOS 13+
- Xcode 15+ (to build)
- API key for Gemini, DeepSeek, OpenAI, or any compatible provider

## License

MIT
