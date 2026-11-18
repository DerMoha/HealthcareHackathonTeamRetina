# Deploying MedSim XR to a physical Vision Pro

Requires **visionOS 26.0 or later** on the headset (minimum of the ElevenLabs/LiveKit SDK) and Xcode 26+ with the visionOS SDK.

## Steps

1. **Developer Mode on the headset**: Settings > Privacy & Security > Developer Mode > On, restart.
2. **Pair**: Mac and Vision Pro on the same Wi-Fi. On the headset: Settings > General > Remote Devices (or Xcode > Window > Devices and Simulators > Connect via Network), accept the pairing code on the Mac. Alternatively use the Developer Strap over USB-C.
3. **Signing**: `cd visionos && cp Config/Local.xcconfig.example Config/Local.xcconfig`, then set `DEVELOPMENT_TEAM` (10-character Team ID from developer.apple.com > Membership). Also set `MEDSIM_BACKEND_HOST` to the Mac's LAN address, e.g. `192.168.1.50:8000`, and `ELEVENLABS_AGENT_ID` if used.
4. Open `MedSimXR.xcodeproj`, pick the Vision Pro as the destination, and run. Trust the developer profile on the headset if asked (Settings > General > VPN & Device Management).
5. **Backend**: run it bound to `0.0.0.0` (not localhost) on the same Wi-Fi as the headset; allow incoming connections in the macOS firewall.
6. **Permission prompts**: accept Microphone, Local Network, and Hand Tracking (only needed for fingertip mode) when asked. If you denied one, fix it in Settings > Apps > MedSim XR.
7. Start a session. In the wrist case, the stool appears about 1.7 m ahead and the patient initially stands closer. Use **Recenter Patient** to place the scene again.

The backend host and agent ID can also be edited in the panel's Settings; they apply on the next Start.

## Only verifiable with the headset

- [ ] Microphone captures speech; patient audio is audible and not echoing.
- [ ] Mixed immersion: real room visible, no full-immersion switch.
- [ ] Placement: patient on the floor, stool ~1.7 m ahead (he stands ~0.4 m closer), facing you; Recenter re-places correctly after turning/moving.
- [ ] Scale: seated head about 1.3 m; forearm rests on thigh without clipping badly.
- [ ] Gaze + pinch on each of the 3 zones triggers the right reaction; zones do not overlap; hover highlight shows.
- [ ] Arm-withdrawal / flinch animation and "Ow!" clip fire on the snuffbox.
- [ ] Fingertip examination (Settings toggle, experimental): touch triggers zones; denial does not break gaze+pinch.
- [ ] Panel remains usable in the headset (text entry, quick-fill diagnosis button, feedback scrolling).
