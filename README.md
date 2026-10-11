# BlindSpot

BlindSpot is an accessibility-first indoor wayfinding prototype for blind and low-vision travelers. This repository currently contains a responsive browser demo with sample Cedar Hall directions.

## Run locally

From the repository root, start any static web server. For example:

```sh
python3 -m http.server 4173
```

Then open `http://localhost:4173`.

## Try the prototype

- Choose a destination and start spoken sample directions.
- Repeat, pause, advance, or end guidance. During guidance, swipe left for the next direction or right to repeat.
- Enable eyes-free focus mode, larger text, high contrast, spoken directions, and haptic cues in Access settings.
- Preview an explicitly labeled sample obstacle alert.

Speech uses the browser's built-in Speech Synthesis API. Haptics use the browser vibration API when available. The prototype does not request location or microphone permissions.

## Gnarly foundation and current limits

The direction is informed by [mukundgaur/gnarly](https://github.com/mukundgaur/gnarly), especially its iOS RoomPlan/ARKit mapper, spatial route waypoints, named landmarks, and shared map data. BlindSpot's web prototype does not capture LiDAR, relocalize in AR, detect live obstacles, or connect to ElevenLabs. Those capabilities require a native iOS application, supported hardware, mapped spaces, and service integration. The floor plan and directions here are sample content and are not safe for real-world wayfinding.
