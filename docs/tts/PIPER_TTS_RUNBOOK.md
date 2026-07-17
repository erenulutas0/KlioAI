# Piper TTS Runbook

Last update: 2026-05-31 Europe/Istanbul

KlioAI uses Piper TTS for low-cost Speaking audio. Backend code maps Flutter voice IDs to flat Piper model filenames under the runtime model directory.

## Runtime Paths

Local Windows backend:

```text
C:\piper
```

Production Docker backend:

```text
/piper
```

Production host mount:

```text
/opt/vocabmaster/piper
```

Backend Piper binary:

```text
/opt/piper/piper
```

## Required Voice Files

Each voice needs both the `.onnx` model and matching `.onnx.json` config.

```text
en_US-amy-medium.onnx
en_US-amy-medium.onnx.json
en_US-ryan-medium.onnx
en_US-ryan-medium.onnx.json
en_US-lessac-medium.onnx
en_US-lessac-medium.onnx.json
en_GB-alan-medium.onnx
en_GB-alan-medium.onnx.json
en_GB-jenny_dioco-medium.onnx
en_GB-jenny_dioco-medium.onnx.json
en_GB-cori-medium.onnx
en_GB-cori-medium.onnx.json
```

## Flutter Voice Mapping

Source:

```text
flutter_vocabmaster/lib/models/voice_model.dart
```

Current voice IDs:

```text
amy -> en_US-amy-medium.onnx
ryan -> en_US-ryan-medium.onnx
lessac -> en_US-lessac-medium.onnx
alan -> en_GB-alan-medium.onnx
jenny_dioco -> en_GB-jenny_dioco-medium.onnx
cori -> en_GB-cori-medium.onnx
```

Backend mapping source:

```text
backend/src/main/java/com/ingilizce/calismaapp/service/PiperTtsService.java
```

## Production Deploy Notes

`/opt/vocabmaster/deploy/docker-compose.app.yml` must mount host Piper models:

```yaml
volumes:
  - ../piper:/piper:ro
```

After changing the mount:

```bash
cd /opt/vocabmaster/deploy
docker compose -f docker-compose.app.yml up -d --no-deps --force-recreate backend
```

## Smoke Test

Inside the production backend container:

```bash
for model in \
  en_US-amy-medium.onnx \
  en_US-ryan-medium.onnx \
  en_US-lessac-medium.onnx \
  en_GB-alan-medium.onnx \
  en_GB-jenny_dioco-medium.onnx \
  en_GB-cori-medium.onnx; do
  printf "Hello test." | /opt/piper/piper --model /piper/$model --output_file /tmp/$model.wav
  test -s /tmp/$model.wav
done
```

If every file is created, Piper can load all voices.

## Common Failure

If all app voices sound like Amy, the backend is probably falling back because only the default model exists or `/piper` is not mounted into the backend container.
