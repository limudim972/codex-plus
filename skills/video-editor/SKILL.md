---
name: video-editor
description: Create and edit Hebrew RTL videos from a brief using the bundled Hebrew Video Editor project, with AI planning, FFmpeg composition, Remotion and HyperFrames motion graphics, subtitles, narration, music, SFX, montages, podcast-to-Reels, and lyric videos. Use for requests to create a Hebrew video, edit clips, make a montage, create Reels or Shorts, produce a lyrics video, or render Hebrew title cards and overlays.
---

# Hebrew Video Editor

Use the bundled project at `source/` as the working directory. It is a Node.js command-line toolkit, not a GUI editor. Preserve user assets and secrets outside the skill source when practical.

## Runtime requirements

- Node.js 22 or newer
- FFmpeg and FFprobe on PATH, or `FFMPEG_PATH`/`FFPROBE_PATH`
- Chrome/Chromium for HyperFrames
- API keys only for the features that need them; load them from `.env`, never hardcode them

Before the first render, inspect `source/SETUP.md` and `source/ASSETS.md`. Install dependencies with `npm install`; install Remotion dependencies in `source/remotion` when using Remotion. Fonts, music, and SFX are not bundled.

## Workflow

1. Collect a brief: topic, audience, type, duration, aspect ratio, source media, logo/brand colors, and delivery destination.
2. Present or record the proposed Hebrew script and wait for approval before rendering when the user is collaborating interactively.
3. Produce a storyboard with shot timing, visuals, motion, transitions, text, SFX, and music; wait for approval when appropriate.
4. Collect or generate assets, compose with FFmpeg, and validate the output with FFprobe and a visual check.
5. Deliver the rendered file to the requested local path. Do not upload to Google Drive or send WhatsApp messages unless the user explicitly requests that external action.

## Commands

Run commands from `source/`:

```powershell
node scripts/video-editor.mjs --brief "..." --client "..."
node scripts/video-editor.mjs --mode montage --input .\greetings --name "נועה" --age 5
node scripts/video-editor.mjs --mode podcast-reels --input podcast.mp4
node scripts/video-editor.mjs --mode lyrics --audio song.mp3 --lyrics lyrics.txt
node scripts/render-overlay.mjs title-card --text "כותרת" --subtitle "כתובית" --out card.webm
npm run catalog
```

For a reusable parameterized composition, use Remotion. For bespoke HTML/GSAP overlays or transparent-alpha WebM, use HyperFrames. Prefer 1080×1920 for vertical video, 1920×1080 for horizontal, and 30 FPS unless the brief says otherwise.

## Hebrew and quality rules

- Keep Hebrew text RTL-safe; subtitles use ASS RTL embedding and correct Hebrew fonts.
- Check for reversed or left-to-right Hebrew before delivery.
- Keep voice clear, music subdued, and SFX below the narration.
- Use a strong hook in the first 1.5 seconds and avoid decorative shots that do not advance the story.
- Probe duration, dimensions, frame rate, codecs, and audio after rendering.
- If a required API key, asset, or system dependency is missing, explain exactly what is missing and continue with a no-key/local path where possible.

For detailed engine architecture and specialized mode guidance, read `source/SKILL.md`; for setup and troubleshooting, read `source/SETUP.md`.
