# AudioCraft Troubleshooting Guide

## Installation Issues

### Import errors
```bash
pip install audiocraft
# Or from GitHub
pip install git+https://github.com/facebookresearch/audiocraft.git
python -c "from audiocraft.models import MusicGen; print('OK')"
```

### FFmpeg not found
```bash
# Ubuntu/Debian
sudo apt-get install ffmpeg
# macOS
brew install ffmpeg
# Windows (conda)
conda install -c conda-forge ffmpeg
```

### PyTorch CUDA mismatch
```bash
nvcc --version
python -c "import torch; print(torch.version.cuda)"
pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu121
```

### xformers issues
```bash
pip install xformers
# Or disable
export AUDIOCRAFT_USE_XFORMERS=0
```

## Model Loading Issues

### Out of memory
```python
# Use smaller model
model = MusicGen.get_pretrained('facebook/musicgen-small')
# Force CPU then move
model = MusicGen.get_pretrained('facebook/musicgen-small', device="cpu")
model = model.to("cuda")
# Use HF with device_map
model = MusicgenForConditionalGeneration.from_pretrained("facebook/musicgen-small", device_map="auto")
```

### Download failures
```python
import os
os.environ["AUDIOCRAFT_CACHE_DIR"] = "/path/to/cache"
# Resume download
from huggingface_hub import snapshot_download
snapshot_download("facebook/musicgen-small", resume_download=True)
```

### Wrong model type
- Text-to-music: `MusicGen.get_pretrained('facebook/musicgen-medium')`
- Text-to-sound: `AudioGen.get_pretrained('facebook/audiogen-medium')`
- Melody conditioning: `musicgen-melody` variant
- Stereo: `musicgen-stereo-medium` variant

## Generation Issues

### Empty or silent output
```python
wav = model.generate(["upbeat music"])
print(f"Max amplitude: {wav.abs().max().item()}")
# Normalize if too quiet
def normalize_audio(audio, target_db=-14.0):
    rms = torch.sqrt(torch.mean(audio ** 2))
    target_rms = 10 ** (target_db / 20)
    return audio * target_rms / (rms + 1e-8)
```

### Poor quality
- Use larger model (large > medium > small)
- Adjust: lower temperature (0.8), higher cfg_coef (4.0), better prompts
- Try MultiBand Diffusion decoder

### Generation too short
```python
model.set_generation_params(duration=30)  # Set before generate
# Max duration is typically 30s
```

### Melody conditioning fails
- Load `musicgen-melody` model (not base model)
- Resample melody to 32kHz
- Convert stereo to mono
- Use `generate_with_chroma([prompt], melody, 32000)`

## Memory Issues

### CUDA out of memory
```python
torch.cuda.empty_cache()
# Reduce duration
model.set_generation_params(duration=10)
# Generate one at a time
for prompt in prompts:
    wav = model.generate([prompt])
    torch.cuda.empty_cache()
# Use CPU
model = MusicGen.get_pretrained(..., device="cpu")
```

### Memory leak during batch
```python
import gc
for prompt in prompts:
    with torch.no_grad():
        wav = model.generate([prompt]).cpu()
    del wav; gc.collect(); torch.cuda.empty_cache()
```

## Audio Format Issues

### Wrong sample rate
- MusicGen: 32kHz
- AudioGen: 16kHz
```python
torchaudio.save("output.wav", wav[0].cpu(), sample_rate=32000)
```

### Stereo/mono mismatch
```python
# Mono to stereo
if wav.shape[1] == 1:
    wav_stereo = wav.repeat(1, 2, 1)
# Use stereo model
model = MusicGen.get_pretrained('facebook/musicgen-stereo-medium')
```

### Clipping
```python
if wav.abs().max().item() > 1.0:
    wav = wav / wav.abs().max().item()
```

## HuggingFace Transformers Issues

Processor and model must match:
```python
processor = AutoProcessor.from_pretrained("facebook/musicgen-small")
model = MusicgenForConditionalGeneration.from_pretrained("facebook/musicgen-small")
```
HF uses different param names: `guidance_scale` (not cfg_coef), `max_new_tokens` (not duration). ~50 tokens per second.

## Performance

### Slow generation
- Use smaller model, reduce duration
- Batch multiple prompts: `model.generate(["a", "b", "c"])` is faster than loop
- Use `torch.compile(model.lm)`

## Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| CUDA out of memory | Model too large | Smaller model, shorter duration |
| ffmpeg not found | FFmpeg not installed | Install FFmpeg |
| No module named 'audiocraft' | Not installed | `pip install audiocraft` |
| Expected 3D tensor | Wrong input shape | Check tensor dimensions |
| KeyError: 'melody' | Wrong model for melody | Use musicgen-melody |
