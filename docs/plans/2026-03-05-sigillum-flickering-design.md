# Sigillum: Flickering Anti-Screenshot Protection

## Overview

New photo sending mode "Sigillum" that combines one-time viewing with a high-frequency noise overlay (flickering) designed to disrupt camera sensors while remaining imperceptible to the human eye.

## UI Flow

1. **Send**: Third button in attachment bottom sheet: "Invia foto con Sigillum" (eye emoji)
2. **Chat bubble**: Sender and recipient see a Sigillum-specific placeholder (distinct from plain one-time)
3. **Full-screen view**: Recipient opens photo wrapped in `FlickerShield` widget
4. **After viewing**: Same as one-time — `viewedOnce: true`, locked placeholder shown

## Data Model (Firestore)

```
messages/{messageId}
  .oneTime: true        // always true for Sigillum (Sigillum implies one-time)
  .sigillum: true       // new field
  .viewedOnce: bool     // unchanged
```

Backward compatible — existing messages without `sigillum` field behave as before.

## Architecture

### New Widget: `FlickerShield`

Location: `lib/widgets/flicker_shield.dart`

Independent from the risk engine. Always active when mounted.

**Flickering specs:**
- Frequency: 60Hz base (never below 50Hz)
- Randomization: +/-10Hz to prevent camera adaptation
- Overlay opacity: 0.3
- Mask type: pre-generated noise pattern textures (3-4 variants, rotated cyclically)
- Performance: `AnimationController` + `RepaintBoundary` to isolate repaints

**Behavior:**
- Alternates between showing content normally and overlaying a noise pattern
- At 60Hz with 0.3 opacity, persistence of vision makes it invisible to humans
- Camera sensors capturing at fixed shutter speeds will pick up noise frames

### Modified Files

- `lib/widgets/flicker_shield.dart` — new widget
- `lib/screens/chat_screen.dart` — Sigillum send button, placeholder, FlickerShield in full-screen
- `lib/services/chat_service.dart` — `sigillum` parameter in `sendImage()`
