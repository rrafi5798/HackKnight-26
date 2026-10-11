# BlindSpot

BlindSpot now includes a native iOS app for LiDAR room capture and ARKit-based, on-device indoor wayfinding. The project is based on the capture, world-map, and ordered-waypoint approach used by [mukundgaur/gnarly](https://github.com/mukundgaur/gnarly).

## Run it on an iPhone

This workspace is running on Linux and cannot compile, sign, or install iOS apps. To install on your LiDAR-equipped iPhone, use a Mac with Xcode 16 or later:

1. Open [`ios/BlindSpot.xcodeproj`](./ios/BlindSpot.xcodeproj) in Xcode.
2. Connect and unlock your iPhone. Select it as the run destination.
3. In the BlindSpot target's **Signing & Capabilities**, choose your Apple developer team. Change the bundle identifier if it conflicts with another app.
4. Build and run. Approve camera access when iOS asks.
5. Open **My spaces**, create a named space, and open the camera scanner.
6. Walk the connected area slowly. Mark the starting point, then mark named destinations in walking order. Finish the scan to save the RoomPlan scan, USDZ preview, ARKit world map, route waypoints, and named landmark metadata on the phone.
7. Select the saved space in **Navigate** and start spatial guidance from the same physical area used during capture. Slowly look around while ARKit relocalizes. Directions begin only after tracking becomes normal.

RoomPlan requires supported hardware; the app checks `RoomCaptureSession.isSupported` at runtime. The project targets iOS 17 or later. Camera permission is requested only when the scanner opens. Scans are stored in the app's Documents directory and are not uploaded.

## What works in this native implementation

- RoomPlan live camera/LiDAR scanning and post-processed room geometry.
- On-device scan storage as JSON plus USDZ preview.
- ARKit world-map capture and restoration for repeat visits to the same physical space.
- Named start/destination landmarks recorded at the phone's live ARKit camera pose.
- Clock-face bearing and distance cues from live ARKit position, with landmark arrival progression; position tracking stops at arrival.
- On-device spoken prompts, VoiceOver announcements, configurable haptics, and a spoken/haptic warning when ARKit loses confirmed position.
- Optional ARKit scene-depth sampling that can announce possible nearby surfaces.
- A route package (`route.json`) using Gnarly's version-1 `arkit-world-meters` ordered-waypoint shape, with additional names/headings in `landmarks.json`.

## Safety and known limits

This is a hardware-dependent engineering prototype, not a safety-certified navigation aid. RoomPlan captures a room/connected area, not a whole campus as a complete routable building graph. Users must record route points while walking the scan; automatic door/stair graph generation, multi-floor transitions, multi-zone map alignment, and route planning between arbitrary endpoints are not implemented. ARKit relocalization can fail or drift, and the app pauses turn progression unless tracking is normal. Depth sampling can mistake floors or walls for nearby surfaces and can miss obstacles. Keep using a cane, guide dog, or other mobility aid, and test only in a controlled familiar space with a sighted collaborator.

ElevenLabs is not connected yet. Native `AVSpeechSynthesizer` currently provides spoken directions. Replace the speech service behind `NavigationVoice` after choosing the ElevenLabs streaming/API integration; do not embed a service API key in the app.

The root browser files are an earlier UI prototype; use the Xcode project for camera capture and ARKit functionality.

## Apple API references

- [RoomPlan](https://developer.apple.com/documentation/roomplan) and [`RoomCaptureView`](https://developer.apple.com/documentation/roomplan/roomcaptureview) provide the camera scanning experience and processed room geometry.
- [`CapturedRoom`](https://developer.apple.com/documentation/roomplan/capturedroom) exposes captured features and USDZ export.
- [`RoomCaptureSession.arSession`](https://developer.apple.com/documentation/roomplan/roomcapturesession/arsession) provides the ARKit session used to save the spatial map.
- [`ARSession.getCurrentWorldMap`](https://developer.apple.com/documentation/arkit/arsession/getcurrentworldmap(completionhandler:)) and [`ARWorldTrackingConfiguration.initialWorldMap`](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/initialworldmap) support saving and relocalizing against the same space.
- [`ARFrame.sceneDepth`](https://developer.apple.com/documentation/arkit/arframe/scenedepth) provides LiDAR depth data on supported devices.
- [`AVSpeechSynthesizer`](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer) speaks direction prompts on device.
