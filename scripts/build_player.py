#!/usr/bin/env python3
"""Build a self-contained captioned player (audio + VTT captions) from an
opencode assistant-history JSONL file. Every sentence becomes a caption cue,
is synthesized to WAV with espeak-ng, and embedded (base64) into one offline
HTML file. Prints the HTML path on the last stdout line."""
import base64
import json
import os
import re
import struct
import subprocess
import sys

ESK = os.path.join(os.path.expanduser("~"), ".local", "espeak-ng", "bin", "espeak-ng")
RATE, PITCH, GAP = 150, 42, 6  # words/min, pitch, word gap ms


def wav_duration(path):
    with open(path, "rb") as f:
        head = f.read(44)
    assert head[:4] == b"RIFF" and head[8:12] == b"WAVE", f"bad wav {path}"
    byte_rate = struct.unpack("<I", head[28:32])[0]
    data_size = struct.unpack("<I", head[40:44])[0]
    return data_size / byte_rate if byte_rate else 1.0


def split_cues(text, max_chars=180):
    text = re.sub(r"\s+", " ", text).strip()
    cues = []
    for s in re.split(r"(?<=[.!?…])\s+", text):
        s = s.strip()
        while len(s) > max_chars:
            cut = s.rfind(",", 0, max_chars)
            if cut < 60:
                cut = s.rfind(" ", 0, max_chars)
            if cut < 60:
                cut = max_chars
            cues.append(s[:cut].strip())
            s = s[cut:].strip()
        if s:
            cues.append(s)
    return cues


def synth(text, out_wav):
    subprocess.run(
        [ESK, "-w", out_wav, "-s", str(RATE), "-p", str(PITCH), "-g", str(GAP), "-v", "en-us", text],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def fmt_ts(sec):
    ms = int(round(sec * 1000))
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms % 60000 // 1000:02d}.{ms % 1000:03d}"


def main():
    history_path, max_msgs, out_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    os.makedirs(out_dir, exist_ok=True)

    entries = []
    with open(history_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except Exception:
                continue
            if e.get("role") == "assistant" and e.get("text"):
                entries.append(e["text"])
    entries = entries[-max_msgs:]

    cues = []
    for e in entries:
        cues.extend(split_cues(e))

    if not cues:
        sys.stderr.write("No assistant replies recorded yet — send a message first.\n")
        print("")
        return

    times, t = [], 0.0
    payload = []
    for i, cue in enumerate(cues):
        wav = os.path.join(out_dir, f"cue_{i:03d}.wav")
        synth(cue, wav)
        d = wav_duration(wav)
        times.append((t, t + d))
        payload.append({
            "start": round(t, 3), "end": round(t + d, 3), "text": cue,
            "wav": base64.b64encode(open(wav, "rb").read()).decode(),
        })
        t += d + 0.25

    vtt_lines = ["WEBVTT", ""]
    for i, (cue, (start, end)) in enumerate(zip(cues, times)):
        vtt_lines.extend([f"{i + 1:03d}", f"{fmt_ts(start)} --> {fmt_ts(end)}", cue, ""])
    vtt_lines.append("")
    vtt = "\n".join(vtt_lines)

    payload_json = json.dumps(payload)
    html = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Captioned read-aloud</title>
<style>
  :root{ --bg:#0d1117; --fg:#f0f4fa; --acc:#7fd6ff; --dim:#8b96a8; }
  *{ box-sizing:border-box; }
  body{ margin:0; background:var(--bg); color:var(--fg);
        font-family:"Atkinson Hyperlegible",Verdana,sans-serif;
        line-height:1.7; letter-spacing:.04em; word-spacing:.12em; padding:24px; }
  h1{ font-size:20px; color:var(--dim); letter-spacing:.2em; text-transform:uppercase; margin:0 0 4px; }
  .sub{ color:var(--dim); font-size:16px; margin-bottom:14px; }
  .ctrls{ display:flex; gap:14px; flex-wrap:wrap; align-items:center; margin:14px 0 20px; }
  button{ font-size:20px; padding:10px 22px; border-radius:10px; border:1px solid #2c3b52;
          background:#141923; color:var(--fg); cursor:pointer; }
  button:hover{ background:#1d2633; }
  .cue{ padding:14px 18px; border-radius:12px; cursor:pointer; border:1px solid transparent;
        margin-bottom:8px; font-size:38px; }
  .cue.active{ background:#16212e; border-color:var(--acc); color:#fff; }
  .cue.done{ opacity:.35; }
  #pos{ font-size:18px; color:var(--acc); min-width:200px; }
  select{ font-size:18px; background:#141923; color:var(--fg); border:1px solid #2c3b52;
          border-radius:8px; padding:6px 10px; }
  .prog{ height:6px; background:#141923; border-radius:3px; margin:0 0 8px; }
  .prog i{ display:block; height:6px; background:var(--acc); width:0%; border-radius:3px; }
</style>
</head><body>
  <h1>Captioned read-aloud</h1>
  <div class="sub">audio + captions &middot; click any line to start there</div>
  <div class="prog"><i id="fill"></i></div>
  <div class="ctrls">
    <button id="play">&#9654; Play / Pause</button>
    <button id="stop">&#9632; Stop</button>
    <label>Speed <select id="speed">
      <option value="0.8">slow</option><option value="1" selected>normal</option>
      <option value="1.25">fast</option>
    </select></label>
    <label>Text size <select id="size">
      <option value="30">medium</option><option value="38" selected>large</option>
      <option value="46">huge</option>
    </select></label>
    <span id="pos">0 / {n} cues</span>
  </div>
  <div id="cues"></div>
<script>
"use strict";
const CUES = {payload_json};
let AC=null, sources=[], playing=false, cueIdx=0, raf=null, last=null, wall=0, estTotal=1;

const $=id=>document.getElementById(id);
const el=document.getElementById("cues");
CUES.forEach((c,i)=>{ const d=document.createElement("div");
  d.className="cue"; d.textContent=c.text;
  d.addEventListener("click",()=>{ if(playing) stopAll(); play(i); });
  el.appendChild(d); });

function ensure(){ if(!AC) AC=new (window.AudioContext||window.webkitAudioContext)(); return AC; }
function kill(){ sources.forEach(s=>{ try{ s.onended=null; s.stop(); }catch(e){} s.disconnect(); }); sources=[]; }
function rate(){ return parseFloat($("speed").value); }

function est(){
  let sum=0, r=rate();
  for(let i=cueIdx;i<CUES.length;i++) sum += (CUES[i].end-CUES[i].start)/r + 0.25;
  return Math.max(1, sum);
}

function play(i){
  if(i>=CUES.length){ stopAll(); return; }
  ensure(); if(AC.state==="suspended") AC.resume();
  kill(); playing=true; cueIdx=i; wall=0; last=null; estTotal=est();
  const cue=CUES[i], src=AC.createBufferSource(); sources=[src];
  src.connect(AC.destination);
  AC.decodeAudioData(b64toAB(cue.wav)).then(buf=>{
    src.buffer=buf; src.playbackRate.value=rate();
    src.start();
    src.onended=()=>{ if(playing && cueIdx===i){ paint(); play(i+1); } };
  });
  paint(); startRaf();
}
function stopAll(){ playing=false; kill(); if(raf) cancelAnimationFrame(raf); paint(); }
function toggle(){ if(playing){ AC.suspend(); playing=false; if(raf) cancelAnimationFrame(raf); }
  else{ if(AC && AC.state==="suspended") AC.resume(); play(cueIdx); } }

function b64toAB(b64){ const bin=atob(b64); const u=new Uint8Array(bin.length);
  for(let i=0;i<bin.length;i++) u[i]=bin.charCodeAt(i); return u.buffer; }

function startRaf(){ last=null; raf=requestAnimationFrame(tick); }
function tick(ts){ if(!playing) return; const now=performance.now();
  if(last!=null){ wall += (now-last)/1000*rate(); }
  last=now; $("fill").style.width = Math.min(100, wall/estTotal*100)+"%";
  raf=requestAnimationFrame(tick); }

function paint(){
  const divs=el.children;
  for(let i=0;i<divs.length;i++){
    divs[i].classList.toggle("active", i===cueIdx);
    divs[i].classList.toggle("done", i<cueIdx);
  }
  if(divs[cueIdx]) divs[cueIdx].scrollIntoView({block:"nearest",behavior:"smooth"});
  $("pos").textContent = Math.min(cueIdx+1,CUES.length)+" / "+CUES.length+" cues";
}

$("play").addEventListener("click", toggle);
$("stop").addEventListener("click", ()=>{ if(playing) stopAll(); });
$("speed").addEventListener("change", ()=>{ if(playing) estTotal=est(); });
$("size").addEventListener("change", e=>{ document.querySelectorAll(".cue")
  .forEach(d=>d.style.fontSize=e.target.value+"px"); });
</script>
</body></html>
""".replace("{payload_json}", payload_json).replace("{n}", str(len(cues)))

    html_path = os.path.join(out_dir, "player.html")
    vtt_path = os.path.join(out_dir, "captions.vtt")
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html)
    with open(vtt_path, "w", encoding="utf-8") as f:
        f.write(vtt)
    print(html_path)


if __name__ == "__main__":
    main()