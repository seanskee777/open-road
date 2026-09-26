import sys
from faster_whisper import WhisperModel

MODEL = WhisperModel("base.en", device="cpu", compute_type="int8")

segs, _ = MODEL.transcribe(sys.argv[1], language="en", beam_size=1)
print(" ".join(s.text.strip() for s in segs).strip())