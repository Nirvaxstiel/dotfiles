# AudioCraft Advanced Usage Guide

## Fine-tuning MusicGen

### Custom dataset preparation

```python
import os
import json
from pathlib import Path
import torchaudio

def prepare_dataset(audio_dir, output_dir, metadata_file):
    """
    Prepare dataset for MusicGen fine-tuning.

    Directory structure:
    output_dir/
    ├── audio/
    │   ├── 0001.wav
    │   ├── 0002.wav
    │   └── ...
    └── metadata.json
    """
    output_dir = Path(output_dir)
    audio_output = output_dir / "audio"
    audio_output.mkdir(parents=True, exist_ok=True)

    # Load metadata (format: {"path": "...", "description": "..."})
    with open(metadata_file) as f:
        metadata = json.load(f)

    processed = []

    for idx, item in enumerate(metadata):
        audio_path = Path(audio_dir) / item["path"]

        # Load and resample to 32kHz
        wav, sr = torchaudio.load(str(audio_path))
        if sr != 32000:
            resampler = torchaudio.transforms.Resample(sr, 32000)
            wav = resampler(wav)

        # Convert to mono if stereo
        if wav.shape[0] > 1:
            wav = wav.mean(dim=0, keepdim=True)

        # Save processed audio
        output_path = audio_output / f"{idx:04d}.wav"
        torchaudio.save(str(output_path), wav, sample_rate=32000)

        processed.append({
            "path": str(output_path.relative_to(output_dir)),
            "description": item["description"],
            "duration": wav.shape[1] / 32000
        })

    # Save processed metadata
    with open(output_dir / "metadata.json", "w") as f:
        json.dump(processed, f, indent=2)

    print(f"Processed {len(processed)} samples")
    return processed
```

### Fine-tuning with dora

```bash
# AudioCraft uses dora for experiment management
pip install dora-search

git clone https://github.com/facebookresearch/audiocraft.git
cd audiocraft

# Create config for fine-tuning
cat > config/solver/musicgen/finetune.yaml << 'EOF'
defaults:
  - musicgen/musicgen_base
  - /model: lm/musicgen_lm
  - /conditioner: cond_base

solver: musicgen
autocast: true
autocast_dtype: float16

optim:
  epochs: 100
  batch_size: 4
  lr: 1e-4
  ema: 0.999
  optimizer: adamw

dataset:
  batch_size: 4
  num_workers: 4
  train:
    - dset: your_dataset
      root: /path/to/dataset
  valid:
    - dset: your_dataset
      root: /path/to/dataset

checkpoint:
  save_every: 10
  keep_every_states: null
EOF

dora run solver=musicgen/finetune
```

### LoRA fine-tuning

```python
from peft import LoraConfig, get_peft_model
from audiocraft.models import MusicGen
import torch

model = MusicGen.get_pretrained('facebook/musicgen-small')
lm = model.lm

lora_config = LoraConfig(
    r=8,
    lora_alpha=16,
    target_modules=["q_proj", "v_proj", "k_proj", "out_proj"],
    lora_dropout=0.05,
    bias="none"
)

lm = get_peft_model(lm, lora_config)
lm.print_trainable_parameters()
```

## Multi-GPU Training

### DataParallel
```python
import torch.nn as nn
if torch.cuda.device_count() > 1:
    model.lm = nn.DataParallel(model.lm)
model.to("cuda")
```

### DistributedDataParallel
```python
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP

def setup(rank, world_size):
    dist.init_process_group("nccl", rank=rank, world_size=world_size)
    torch.cuda.set_device(rank)

# ... standard DDP training loop
```

## Custom Conditioning

```python
from audiocraft.modules.conditioners import BaseConditioner

class CustomConditioner(BaseConditioner):
    def __init__(self, dim, output_dim):
        super().__init__(dim, output_dim)
        self.embed = torch.nn.Linear(dim, output_dim)

    def forward(self, x):
        return self.embed(x)
```

## EnCodec Deep Dive

```python
from audiocraft.models import CompressionModel

encodec = CompressionModel.get_pretrained('facebook/encodec_32khz')
print(f"Sample rate: {encodec.sample_rate}")
print(f"Cardinality: {encodec.cardinality}")
print(f"Num codebooks: {encodec.num_codebooks}")
print(f"Frame rate: {encodec.frame_rate}")

# Lower bandwidth = more compression
encodec.set_target_bandwidth(6.0)  # 6 kbps
encoded = encodec.encode(audio)
decoded = encodec.decode(encoded[0])
```

## MultiBand Diffusion (Enhanced Quality)

```python
from audiocraft.models import MusicGen, MultiBandDiffusion

model = MusicGen.get_pretrained('facebook/musicgen-medium')
mbd = MultiBandDiffusion.get_mbd_musicgen()
model.set_generation_params(duration=10)

gen_tokens = model.generate_tokens(["epic orchestral music"])
wav_mbd = mbd.tokens_to_wav(gen_tokens)
```

## API Server Deployment

### FastAPI server
```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import torchaudio
import io, base64

app = FastAPI()
model = MusicGen.get_pretrained('facebook/musicgen-small')
model.set_generation_params(duration=10)

@app.post("/generate")
async def generate(request: GenerateRequest):
    model.set_generation_params(duration=min(request.duration, 30))
    wav = model.generate([request.prompt])
    buffer = io.BytesIO()
    torchaudio.save(buffer, wav[0].cpu(), sample_rate=32000, format="wav")
    return {"audio_base64": base64.b64encode(buffer.read()).decode()}
```

## LangChain Tool Integration

```python
from langchain.tools import BaseTool
import tempfile

class MusicGeneratorTool(BaseTool):
    name = "music_generator"
    description = "Generate music from a text description."

    def __init__(self):
        super().__init__()
        self.model = MusicGen.get_pretrained('facebook/musicgen-small')
        self.model.set_generation_params(duration=15)

    def _run(self, description: str) -> str:
        with torch.no_grad():
            wav = self.model.generate([description])
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            torchaudio.save(f.name, wav[0].cpu(), sample_rate=32000)
            return f"Generated music saved to: {f.name}"
```

## Post-Processing Pipeline

```python
class AudioPostProcessor:
    def __init__(self, sample_rate=32000):
        self.sample_rate = sample_rate

    def normalize(self, audio, target_db=-14.0):
        rms = torch.sqrt(torch.mean(audio ** 2))
        target_rms = 10 ** (target_db / 20)
        return audio * target_rms / (rms + 1e-8)

    def fade_in_out(self, audio, fade_duration=0.1):
        fade_samples = int(fade_duration * self.sample_rate)
        fade_in = torch.linspace(0, 1, fade_samples)
        fade_out = torch.linspace(1, 0, fade_samples)
        audio[..., :fade_samples] *= fade_in
        audio[..., -fade_samples:] *= fade_out
        return audio

    def process(self, audio):
        audio = self.normalize(audio)
        audio = self.fade_in_out(audio)
        return audio
```
