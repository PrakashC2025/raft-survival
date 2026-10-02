# Instructions for coding agents

Read [GAME_GUIDE.md](GAME_GUIDE.md) before modifying this game. It describes current architecture, controls, gameplay, save formats, Android failures, verification and extension rules. Live source is authoritative; `DOCUMENTATION.md` contains historical snapshots that may be outdated.

- Follow the owner's latest instructions. They currently want source changes and will build the APK manually. Do not export/build an APK unless asked again.
- Temporary testing supplies are enabled: 2,000 each of Wood, Rope, Plastic, Barrel, Stone and Metal, once per save. Preserve this default unless asked to change it.
- Preserve unrelated workspace changes and actual player saves. Run tests using isolated data storage through `tools/verify_source.ps1`; do not reset the owner's normal `user://` directory.
- Source-test staging directories contain junctions to real project folders. Never recursively delete through those junctions.
- Keep required imported island textures in Android exports. Reload editor export settings after external preset edits and verify actual packaged data when an APK is exported.
- Maintain touch action ownership/release, first/third person visuals, capacity-safe inventory operations, foundation grid/support, and backwards-compatible restoration for affected changes.
- Update `GAME_GUIDE.md` when behavior, defaults, architecture, controls or saved data change. Keep build/asset notes accurate when affected.
- Report what was verified accurately. Headless source checks and desktop renderer previews do not prove phone FPS or a freshly exported APK.
