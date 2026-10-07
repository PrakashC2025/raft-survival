# New Game video — 2026-10-07

The owner supplied **WhatsApp Video 2026-10-07 at 10.53.52 AM.mp4** for the game intro. Their latest request removes the added narrator: the original soundtrack is now the only audio, with readable scene subtitles. The film includes its original visible Veo mark. Its upstream source/license has not been independently established; this supplied film is not labeled CC0. No additional paid/downloaded creative assets were added.

- Source: 848 × 478, H.264/AAC, about 31.02 seconds, variable frame timing. Original SHA-256: `5AAF3B0B7E8EC40BAD6B7F49AB296F8813D10D082E92D277E5D352CEAAC54605`.
- Bundled film: `new_game_intro.ogv`, 848 × 480 (one black padding row each side), constant 24 fps, Theora quality 7, 48-frame keyframes, stereo 48 kHz Vorbis quality 4. Mild compression-noise filtering and a 0.35-second opening fade preserve the source picture and marks. The audio replacement copies the existing video stream without another lossy video encode.
- Sound: original soundtrack at full amplitude, with a clipping limiter and brief opening/ending fades. Original expressive delivery, effects and music are retained; no synthetic narration is mixed over them. Captions follow the eight scene intervals in `scripts/flooded_world_intro.gd`.
- `intro_arrival.jpg`: extracted near 30.85 seconds from the supplied film, used only for natural completion and scene entry. Skip holds the current decoder texture instead, without a GPU image readback.
- Runtime: a single VideoStreamPlayer decodes the embedded sound and film. Subtitle timing follows its stream position. No FFmpeg, speech synthesizer, external service, or video interpolation runs in the game.

Offline preparation is reproducible with `tools/prepare_intro_video.py --ffmpeg <executable>`; it no longer loads narration files. The portable converter used was imageio-ffmpeg 0.6.0's FFmpeg 7.1 build with libtheora/libvorbis. Its distribution license records are retained under `tools/media_runtime/`. The converter and historical source/narration work files are ignored by Godot/Git and excluded from Android exports; preparation scripts are source tools only. Keep both bundled files in `video/` in exports.

Encoding follows the official [Godot video guidance](https://docs.godotengine.org/en/stable/tutorials/animation/playing_videos.html). This resolution and frame rate reduce decoding work; real Android playback still requires testing after manual export.
