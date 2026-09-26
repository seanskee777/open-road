import type { Plugin } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin"
import { homedir } from "node:os"
import { join } from "node:path"
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"

const BASE = join(homedir(), ".config", "opencode")
const MUTE_FILE = join(BASE, "assist-mute.json")
const HISTORY_FILE = join(BASE, "assist-history.jsonl")
const PLAYER_DIR = join(BASE, "assist-player")
const SPEAK = join(homedir(), ".local", "opencode-assist", "speak.sh")
const VENV_PY = join(homedir(), ".local", "opencode-assist", "bin", "python")
const DICTATE = join(homedir(), ".local", "opencode-assist", "dictate.py")
const BUILD_PLAYER = join(homedir(), ".local", "opencode-assist", "build_player.py")

const out = (...a: unknown[]) => console.log("[dyslexia]", ...a)

function isMuted(): boolean {
  try {
    return JSON.parse(readFileSync(MUTE_FILE, "utf8")).muted === true
  } catch {
    return false
  }
}
function setMuted(v: boolean) {
  mkdirSync(BASE, { recursive: true })
  writeFileSync(MUTE_FILE, JSON.stringify({ muted: v }))
}
function logHistory(role: string, text: string) {
  try {
    mkdirSync(BASE, { recursive: true })
    appendFileSync(HISTORY_FILE, JSON.stringify({ role, time: Date.now(), text }) + "\n")
  } catch (e) {
    out("logHistory", e)
  }
}

function sanitize(text: string): string {
  return text
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/[#*_>`|~]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
}

/* serialized speech queue so reads never overlap */
let voice: Promise<void> = Promise.resolve()

export default (async ({ $ }) => {
  const say = (text: string) => {
    const clean = sanitize(text)
    if (!clean) return
    const chunks: string[] = []
    let rest = clean
    while (rest.length > 380) {
      const cut = Math.max(rest.lastIndexOf(". ", 380), rest.lastIndexOf(", ", 380), 380)
      chunks.push(rest.slice(0, cut).trim())
      rest = rest.slice(cut).trim()
    }
    if (rest) chunks.push(rest)
    voice = voice
      .then(async () => {
        for (const c of chunks) {
          await $`${SPEAK} ${c}`
        }
      })
      .catch((e) => out("say", e))
  }

  const transcribe = async (wav: string) => {
    const r = await $`${VENV_PY} ${DICTATE} ${wav}`.text()
    return r.trim()
  }
  const record = async (secs: number) => {
    const wav = "/tmp/opencode-assist-rec.wav"
    try {
      await $`arecord -q -f S16_LE -r 16000 -c 1 -d ${String(secs)} ${wav}`
    } catch {
      await $`pw-record --format=s16 --rate=16000 --channels=1 ${wav}`
    }
    return wav
  }
  const openPlayer = async (maxMsgs: number) => {
    mkdirSync(PLAYER_DIR, { recursive: true })
    const r = await $`${VENV_PY} ${BUILD_PLAYER} ${HISTORY_FILE} ${String(maxMsgs)} ${PLAYER_DIR}`.text()
    const html = r.trim().split("\n").pop() ?? ""
    if (html) await $`xdg-open ${html}`
    return html
  }

  /* auto read-aloud, keyed per message and deduped so a reply is spoken once */
  const pendingByMsg = new Map<string, string>()
  const timersByMsg = new Map<string, ReturnType<typeof setTimeout>>()
  const spoken = new Set<string>()

  const flushMsg = (id: string) => {
    const timer = timersByMsg.get(id)
    if (timer) clearTimeout(timer)
    timersByMsg.delete(id)
    if (spoken.has(id)) {
      pendingByMsg.delete(id)
      return
    }
    const text = (pendingByMsg.get(id) ?? "").trim()
    pendingByMsg.delete(id)
    if (!text) return
    spoken.add(id)
    logHistory("assistant", text)
    if (!isMuted()) say(text)
  }
  const key = (part: any, msgId?: string) =>
    msgId ?? (typeof part?.messageID === "string" ? part.messageID : "stream:" + spoken.size)

  const accumulate = (part: { type?: string; text?: string; role?: string; messageID?: string }) => {
    if (!part || part.type !== "text" || typeof part.text !== "string" || part.text.length === 0) {
      return
    }
    const id = key(part)
    pendingByMsg.set(id, (pendingByMsg.get(id) ?? "") + part.text)
    const existing = timersByMsg.get(id)
    if (existing) clearTimeout(existing)
    if ((pendingByMsg.get(id) ?? "").length > 6000) flushMsg(id)
    else timersByMsg.set(id, setTimeout(() => flushMsg(id), 900))
  }

  return {
    "chat.message": async (input, output) => {
      try {
        const message = output.message as { role?: string; id?: string }
        const isAssistant = Boolean(input.model) || message?.role === "assistant"
        if (!isAssistant) return
        const text = (output.parts ?? [])
          .filter((p) => p.type === "text")
          .map((p) => (p as { text?: string }).text ?? "")
          .join("")
          .trim()
        if (!text) return
        const id = message?.id ?? "chat:" + text.slice(0, 32)
        if (spoken.has(id)) return
        const timer = timersByMsg.get(id)
        if (timer) clearTimeout(timer)
        timersByMsg.delete(id)
        pendingByMsg.delete(id)
        spoken.add(id)
        logHistory("assistant", text)
        if (!isMuted()) say(text)
      } catch (e) {
        out("chat.message", e)
      }
    },

    event: async (input) => {
      try {
        const ev = (input as { event?: { type: string; properties?: Record<string, any> } }).event
        if (!ev || ev.type !== "message.part.updated") return
        const part = ev.properties?.part
        if (!part) return
        if (part.type === "step-finish" || part.type === "message-finish") {
          const id = key(part, ev.properties?.messageID)
          flushMsg(id)
          return
        }
        if (part.role !== "assistant") return
        accumulate(part)
      } catch (e) {
        /* event bus shape varies by version; ignore */
        void e
      }
    },

    tool: {
      assist_speak: tool({
        description:
          "Read text aloud in Seven's voice. On-demand only — auto-read is muted. Just type what you want to hear.",
        args: { text: tool.schema.string().describe("Text to speak aloud") },
        async execute({ text }: { text: string }) {
          logHistory("assistant", `(read aloud) ${text}`)
          say(text)
          return "Speaking it aloud now."
        },
      }),

      assist_listen: tool({
        description:
          "Record the microphone for N seconds and transcribe speech to text (faster-whisper). Use for dictation instead of typing.",
        args: {
          seconds: tool.schema.number().optional().describe("Recording time in seconds (default 10, max 120)"),
        },
        async execute({ seconds }: { seconds?: number }) {
          const dur = Math.min(120, Math.max(2, Math.round(seconds ?? 10)))
          const wav = await record(dur)
          const text = await transcribe(wav)
          return text || "(heard nothing — try again or raise the mic level)"
        },
      }),

      assist_mute: tool({
        description: "Turn auto read-aloud of assistant replies on or off.",
        args: { muted: tool.schema.boolean().describe("true silences auto read-aloud") },
        async execute({ muted }: { muted: boolean }) {
          setMuted(muted)
          return muted ? "Auto read-aloud is OFF." : "Auto read-aloud is ON. Ask me anything."
        },
      }),

      assist_player: tool({
        description:
          "Build and open a captioned audio player (audio + VTT subtitles) of the last few assistant replies, for listen-and-read-along.",
        args: {
          messages: tool.schema.number().optional().describe("How many recent replies to include (default 6)"),
        },
        async execute({ messages }: { messages?: number }) {
          const html = await openPlayer(messages ?? 6)
          return html ? `Opened captioned player: ${html}` : "No transcript yet — ask me something, then run again."
        },
      }),
    },
  }
}) satisfies Plugin