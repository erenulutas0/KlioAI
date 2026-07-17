# TTS Provider Strategy

Last update: 2026-05-31 Europe/Istanbul

## Current Choice

Use Piper as the production default.

Reasons:

- No per-character API cost.
- Runs on the existing VPS CPU.
- Good enough for early production while user volume is low.
- Easy to deploy as flat `.onnx` files.

## Candidate Providers

### Piper

Best default for KlioAI now. The main quality issue is usually voice selection and model variety, not provider cost.

Use for:

- Free and premium Speaking playback.
- Fast low-cost voice samples.
- Server-side generation without external TTS bills.

### Kokoro

Good next A/B candidate. It may sound more natural than Piper, but integration and latency need a real VPS test before replacing Piper.

Use for:

- Experimental provider.
- Selected premium speaking sessions after benchmarking.

### Chatterbox

Potentially stronger for expressive voices and character-like speaking partners, but heavier to host.

Use later for:

- Premium expressive voices.
- Character-heavy roleplay.
- Voice-lab style features.

Do not make it the default before there is enough user demand or revenue to justify GPU infrastructure.

## Recommended Roadmap

1. Keep Piper as default and install multiple voices.
2. Add provider abstraction only when Kokoro is actually tested.
3. Run A/B latency and quality smoke checks.
4. Consider Chatterbox after Speaking retention proves valuable.
