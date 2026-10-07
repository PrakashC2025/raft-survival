# New Game video — 2026-10-07

The owner supplied **WhatsApp Video 2026-10-07 at 10.53.52 AM.mp4** and explicitly requested its use as the game intro, with video audio, spoken narration and subtitles. The film includes its original visible Veo mark. Its upstream source/license has not been independently established; this supplied film is not labeled CC0. No additional paid/downloaded creative assets were added.

- Source: 848 × 478, H.264/AAC, about 31.02 seconds, variable frame timing. Original SHA-256: `5AAF3B0B7E8EC40BAD6B7F49AB296F8813D10D082E92D277E5D352CEAAC54605`.
- Bundled film: `new_game_intro.ogv`, 848 × 480 (one black padding row each side), constant 24 fps, Theora quality 7, 48-frame keyframes, stereo 48 kHz Vorbis quality 4. Size: 12,378,678 bytes. Mild compression-noise filtering and a 0.35-second opening fade preserve the source picture and marks.
- Sound: original soundtrack at 26% amplitude, mixed with eight locally synthesized Microsoft David Desktop narration lines, normalized to -16 LUFS before mixing, limited against clipping and faded at the ends. This is synthetic English narration, not a human actor. The words and times match `scripts/flooded_world_intro.gd` CUES. All lines finish within their corresponding cues.
- `intro_arrival.jpg`: extracted near 30.85 seconds from the supplied film, used only for natural completion and scene entry. Skip holds the current decoder texture instead, without a GPU image readback.
- Runtime: a single VideoStreamPlayer decodes the embedded sound and film. Subtitle timing follows its stream position. No FFmpeg, speech synthesizer, external service, or video interpolation runs in the game.

Offline preparation is reproducible with `tools/prepare_intro_narration.ps1` and `tools/prepare_intro_video.py --ffmpeg <executable>`. The portable converter used was imageio-ffmpeg 0.6.0's FFmpeg 7.1 build with libtheora/libvorbis. Its distribution license records are retained under `tools/media_runtime/`. The converter and local source/narration work files are ignored by Godot/Git and excluded from Android exports; preparation scripts are source tools only. Keep both bundled files in `video/` in exports.

Encoding follows the official [Godot video guidance](https://docs.godotengine.org/en/stable/tutorials/animation/playing_videos.html). This resolution and frame rate reduce decoding work; real Android playback still requires testing after manual export.
