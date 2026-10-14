---
name: ai-music-production
description: "AI music generation, songwriting craft, and audio analysis tools — Suno, AudioCraft, HeartMuLa, songsee."
version: 1.0.0
author: Hermes Agent (consolidated from songwriting-and-ai-music, audiocraft-audio-generation, heartmula, songsee)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [music, ai-music, suno, audiocraft, heartmula, songwriting, audio-generation, spectrogram]
---

# AI Music Production

Craft song lyrics, generate music with AI (Suno, AudioCraft, HeartMuLa), and analyze audio with spectrograms. All in one workflow.

## §1 — Songwriting & Lyric Craft

### Song Structure Options
```
ABABCB  Verse/Chorus/Verse/Chorus/Bridge/Chorus    (most pop/rock)
AABA    Verse/Verse/Bridge/Verse                   (jazz standards, ballads)
ABAB    Verse/Chorus alternating                    (simple, direct)
AAA     Verse/Verse/Verse (strophic)                (folk, storytelling)
```

### Rhyme Types (tight to loose)
- **Perfect**: lean/mean
- **Family**: crate/braid
- **Assonance**: had/glass (same vowels, different endings)
- **Consonance**: scene/when (different vowels, similar endings)
- **Near/slant**: enough to suggest connection without locking it down

Mix them. All perfect sounds like a nursery rhyme; all slant sounds lazy.

### Emotional Arc
Mapping energy across the song: Intro 2-3 → Verse 5-6 → Pre-Chorus 7 → Chorus 8-9 → Bridge varies → Final Chorus 9-10.

Key trick: **CONTRAST.** Whisper before a scream. Sparse before dense. The drop only works because of the buildup.

### Parody / Adaptation
1. Map original structure (syllables per line, rhyme scheme, stressed beats)
2. Match stressed syllables to same beats
3. Vowel match on held notes (if original holds "LOOOVE" with "oo", "FOOOD" fits better than "LIFE")
4. Keep some original lines for recognizability

---

## §2 — Suno AI Prompt Engineering

### Style Field Formula
```
Genre + Mood + Era + Instruments + Vocal Style + Production + Dynamics
```
**BAD**: "sad rock song"
**GOOD**: "Cinematic orchestral spy thriller, 1960s Cold War era, smoky sultry female vocalist, big band jazz, sweeping strings, minor key, vintage analog warmth"

### Describe the Journey
"Begins as a haunting whisper over sparse piano. Gradually layers in muted brass. Builds through the chorus with full orchestra. Outro strips back to a lone piano and a fragile whisper fading to silence."

### Metatags (in [brackets] inside lyrics)
**Structure**: [Intro] [Verse] [Pre-Chorus] [Chorus] [Bridge] [Outro] [Guitar Solo] [Instrumental Break]
**Vocal**: [Whispered] [Spoken Word] [Belted] [Falsetto] [Soulful] [Raspy] [Breathy] [Harmonies] [Choir]
**Dynamics**: [High Energy] [Low Energy] [Building Energy] [Explosive] [Emotional Climax]
**Atmosphere**: [Melancholic] [Euphoric] [Nostalgic] [Aggressive] [Dreamy] [Intimate] [Dark Atmosphere]
**SFX**: [Vinyl Crackle] [Rain] [Applause] [Static] [Thunder]

### Custom Mode Rules
- Always use Custom Mode (separate Style + Lyrics)
- Lyrics limit: ~3,000 chars (~40-60 lines)
- Add structural tags in lyrics — without them Suno defaults to flat verse/chorus

### Phonetic Tricks
- Spell words as they SOUND: "through" → "thru"
- ALL CAPS = louder; "lo-o-o-ove" = sustained/melisma
- "...ellipses..." = dramatic pause
- Spell out numbers: "24/7" → "twenty four seven"
- Space acronyms: "AI" → "A I"
- Test proper nouns in 30s clip first

### Workflow
1. Concept/hook first — what's the emotional core?
2. Write lyrics into structure
3. Build Suno style description — paint the dynamic journey
4. Add metatags for performance direction
5. Generate 3-5 variations minimum
6. Use Extend/Continue on promising sections
7. Expect ~3-5 generations per 1 good result

---

## §3 — AudioCraft (Meta MusicGen / AudioGen)

Open-source text-to-music and text-to-sound generation.

### Quick Start
```python
from audiocraft.models import MusicGen
import torchaudio

model = MusicGen.get_pretrained('facebook/musicgen-small')
model.set_generation_params(duration=8, top_k=250, temperature=1.0)

descriptions = ["happy upbeat electronic dance music with synths"]
wav = model.generate(descriptions)
torchaudio.save("output.wav", wav[0].cpu(), sample_rate=32000)
```

### Model Variants
| Model | Size | Use |
|-------|------|-----|
| `musicgen-small` | 300M | Quick generation |
| `musicgen-medium` | 1.5B | Balanced |
| `musicgen-large` | 3.3B | Best quality |
| `musicgen-melody` | 1.5B | Melody conditioning |
| `musicgen-stereo-*` | Varies | Stereo output |
| `audiogen-medium` | 1.5B | Sound effects |

### Melody-Conditioned Generation
```python
model = MusicGen.get_pretrained('facebook/musicgen-melody')
model.set_generation_params(duration=30)
melody, sr = torchaudio.load("melody.wav")
wav = model.generate_with_chroma(["acoustic guitar folk song"], melody, sr)
```

### Using HuggingFace Transformers
```python
from transformers import AutoProcessor, MusicgenForConditionalGeneration
import scipy

processor = AutoProcessor.from_pretrained("facebook/musicgen-small")
model = MusicgenForConditionalGeneration.from_pretrained("facebook/musicgen-small")
model.to("cuda")

inputs = processor(text=["80s pop track with bassy drums"], padding=True, return_tensors="pt").to("cuda")
audio_values = model.generate(**inputs, do_sample=True, guidance_scale=3, max_new_tokens=256)
scipy.io.wavfile.write("output.wav", rate=model.config.audio_encoder.sampling_rate, data=audio_values[0, 0].cpu().numpy())
```

---

## §4 — HeartMuLa (Open-Source Music Generation)

Open-source Suno alternative. Generates full songs from lyrics + tags.

### Installation
```bash
git clone https://github.com/HeartMuLa/heartlib.git
cd heartlib
uv venv --python 3.10 .venv
. .venv/bin/activate
uv pip install -e .
# Fix dependencies:
uv pip install --upgrade datasets transformers
```

### Hardware
- Minimum: 8GB VRAM with `--lazy_load true`
- Recommended: 16GB+ VRAM
- 3B model with lazy_load: ~6.2GB VRAM peak

### Patch for transformers 5.x
In `src/heartlib/heartmula/modeling_heartmula.py`, add to `setup_caches`:
```python
from torchtune.models.llama3_1._position_embeddings import Llama3ScaledRoPE
for module in self.modules():
    if isinstance(module, Llama3ScaledRoPE) and not module.is_cache_built:
        module.rope_init()
        module.to(device)
```

### Download Checkpoints
```bash
cd heartlib
hf download --local-dir './ckpt' 'HeartMuLa/HeartMuLaGen'
hf download --local-dir './ckpt/HeartMuLa-oss-3B' 'HeartMuLa/HeartMuLa-oss-3B-happy-new-year'
hf download --local-dir './ckpt/HeartCodec-oss' 'HeartMuLa/HeartCodec-oss-20260123'
```

---

## §5 — Songsee (Audio Analysis / Spectrograms)

Generate spectrograms and multi-panel audio feature visualizations.

### Setup
```bash
go install github.com/steipete/songsee/cmd/songsee@latest
```
Optional: `ffmpeg` for formats beyond WAV/MP3.

### Usage
```bash
# Basic spectrogram
songsee track.mp3

# Multi-panel visualization grid
songsee track.mp3 --viz spectrogram,mel,chroma,hpss,selfsim,loudness,tempogram,mfcc,flux

# Time slice
songsee track.mp3 --start 12.5 --duration 8 -o slice.jpg
```

### Visualization Types
`spectrogram`, `mel`, `chroma`, `hpss` (harmonic/percussive), `selfsim`, `loudness`, `tempogram`, `mfcc`, `flux`

### Common Flags
`--style classic|magma|inferno|viridis|gray`, `--width`/`--height`, `--window`/`--hop`, `--min-freq`/`--max-freq`, `--format jpg|png`

Output images can be inspected with `vision_analyze` for automated analysis.
