# Score sound — design

2026-08-04. The score sound removed earlier does not return; this is a new,
motivating reward chime, auditioned as WAV candidates and chosen by ear
(candidate "2-arpej" from the first round, plain — no splash layer).
**The approved waveform is the spec**: port the synthesis below
sample-for-sample; resist "improving" the math.

## Chosen sound

A rising pluck arpeggio, marimba-ish voices, normalized to 0.8 peak,
44.1 kHz mono. Envelope: 4 ms linear attack, 50 ms linear release, applied
to the whole canvas.

Pluck voice (t in seconds from note start):

```
pluck(t, f) = sin(2π f t)·e^(−14 t) + 0.22·sin(2π·4f·t)·e^(−14·3.2·t)
```

- **Two points** (duration 0.52 s): notes C5 E5 G5
  (523.25, 659.25, 783.99 Hz), one note every 72 ms,
  note k gain `1 + 0.12k`. Each note's tail runs to the end of the buffer.
- **Three points** (duration 0.60 s): notes C5 E5 G5 C6 (adds 1046.5 Hz),
  faster — one note every 62 ms, same gain ramp, plus a shimmer tail
  placed at 4·62 ms: `0.12·(sin(2π·3100·t) + sin(2π·3100·1.007·t))·e^(−10 t)`
  for 0.3 s.

Reference implementation: `arpeggio()` in the session's
`score-candidates.py` (scratchpad); audition files
`~/Desktop/NotchBasket-skor-adaylari/2-arpej-{2lik,3luk}.wav`.

## Integration

- `ScoreChimeSynthesizer` enum joins the other synthesizers in
  `AudioService.swift` — `samples(sampleRate:threePointer:)`, plus
  `duration(threePointer:)`. No new file, so no pbxproj edits.
- `SoundEffect` gains `scoreTwo` and `scoreThree` cases (the deleted
  `score` case name is not reused). Buffers are synthesized once at init
  like every other effect; default cooldown (0.11 s) applies.
- `BasketballScene` plays the matching effect at the moment a score is
  registered (same code path buzzer-beaters already flow through),
  intensity 1, subject to `soundEnabled` and master volume as usual.

## Tests

Same style as the other synthesizer tests, and each must fail if the
synthesis is deleted or mangled:

- Both variants: silent endpoints, full body (RMS over the middle), peak
  normalized to 0.8.
- The three-point variant is distinguishable: longer than the two-point
  variant and contains C6 energy the two-point variant lacks.
- Scene-level: scoring plays `scoreTwo` for a 2-pointer and `scoreThree`
  for a 3-pointer (via the existing sound-spy seam if present, else a
  policy-level assertion on the effect chosen for a points value).
