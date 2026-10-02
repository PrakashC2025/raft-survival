# Mobile build status

Target: 4 GB Android phones, ARM64. The new <=4.5 GB profile caps at 30 FPS, starts at 70% 3D resolution, uses 1024 shadow maps, lower rain/vegetation budgets and fewer animals. Wildlife farther than 100 m skips movement/AI; model resources are shared. A desktop-forced low profile is a functional simulation, not evidence of FPS or RAM usage on a real phone.

New CC0 online assets replace the third-person block body, birds, sharks, boars, fish, campfire base, ore rocks and several held objects. Survivor has idle/run/jump clips and an arm-pose correction for the legacy rig; boar has walk/attack clips. Bird and shark are static meshes moved by gameplay, not fully articulated animations. Seeds remain small adapted stone-mesh proxies. First-person hands and some craftable pieces still use primitive geometry. This is low-poly art, not photorealism.

Checks passed: imported-model geometry and animation inventory, low-profile full campaign regression, crafting, bonfire placement, crop persistence, cooking and desktop model visual inspection. Fixed journal touch input leaking into camera/movement. Android debug APK is generated separately at build/OceanSurvival-mobile-preview.apk; existing build/OceanSurvival.apk is preserved.

Outstanding: real-phone RAM/FPS/thermal/touch testing; long-session stability; full wildlife animation and broader art polish. Existing source asset licenses outside the new CC0 additions remain unaudited. Headless test shutdown reports six ObjectDB instances; engine editor shutdown also emits an EditorSettings warning after successful APK verification.

Sources and licenses: MOBILE_ASSET_CREDITS.md. No purchases were made.
