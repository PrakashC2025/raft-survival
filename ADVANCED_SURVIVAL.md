# Advanced survival update

This adds a playable mission progression loop to the existing survival world. It does not implement every system in the owner's 106-point world-design document.

## Playing the missions

The mission card shows your level and next required task. Open Bag → Craft for portable equipment. Use BUILD, then NEXT to cycle structures; new machine entries follow RainCollector. Expand foundations to get free supported equipment sockets. Locked structures have a red preview and cannot spend materials. Existing equipment, structures and temporary testing supplies are retained.

| Level | Mission | Unlock |
| --- | --- | --- |
| 1 | Craft Fishing Rod + Spear, build Bonfire | Base tools, farming, cooking, hunting, construction |
| 2 | Build WaterPurifier and collect two distilled portions | Fuel-fired seawater still |
| 3 | Build WindGenerator + ElectricLamp and generate power | Turbine, battery and lamp |
| 4 | Build ElectricPurifier and collect two powered portions | Powered purification and Diving Tank |
| 5 | Build RescueRadio and transmit a powered SOS | Rescue radio |
| 6 | SOS complete; continue surviving and exploring | All new equipment |

Aim at machines and press USE/E. A still uses one Wood for 40 active seconds, producing two Water at 20 seconds each. Finished water remains in its five-portion tank until collected; a full bag cannot delete it. This is seawater distillation by heat, not a simple freshwater filter.

An exposed turbine generates 0.75 charge/second, or 1.8 in rain, up to 120. Its battery automatically powers equipment within 12 m. Powered purification uses 0.3 charge/second and takes 10 seconds per Water. The lamp uses 0.08/second; USE switches it off. The radio needs 20 charge for each SOS; insufficient power consumes nothing. Reserve charge and machine work pause with gameplay and survive Continue.

Oxygen depletes underwater, regenerates at the surface and causes drowning damage at zero. The Diving Tank equips once and slows oxygen consumption from 5 to 1.2 points/second. It is an assisted-breathing game mechanic, replenished by surfacing. Stamina drains during fast swimming/sprinting and recovers during rest. Wetness rises in water and dries gradually. Bandage costs two Rope and restores 25 health when used below full health.

## Flooded-world opening and practical survival

New Game plays an audio-timed photographic cinematic of about 26 seconds: space/asteroid, coastal city, flood, then a lone survivor waking on a raft. It is animated artwork with pans and fades, not a rendered city or a recorded video. SKIP STORY advances to world preparation; BACK TO MENU cancels the choice without replacing saves. Continue and Quick Save go directly to their saved worlds. One atlas texture and simple drawing keep cinematic rendering inexpensive; resource loading runs behind it. Actual world initialization can still take time on a device.

The voyage chart identifies the flooded world and rare surviving islands. The 95-percent figure is story context, not a dynamically simulated planetary flood. Existing island destinations and saved structure positions are preserved. Other survivor NPCs and underwater broken-city exploration are intentionally reserved for later.

Craft a Torch for 2 Wood + 1 Rope, move it from the bag into a hotbar slot and select it. USE/LIGHT near a burning campfire (within 3 m) spends 1 Wood and lights it for 180 seconds of held use. USE/PUT OUT extinguishes it. It has first/third person geometry, flame and a shadowless warm light. Swimming and exposed rain extinguish it; roofs shelter it. Fuel is saved, and stowing it preserves remaining fuel. Wetness rises in exposed rain/water and dries faster beside your held flame. This is simplified playable survival logic, not a physics-accurate fire model.

Rain barrels collect one fresh Water every 20 active seconds of exposed rain, hold 12 portions and save their fill/work. Roofs stop collection. The visible water level follows storage; a full bag preserves it. Gulls feed near islands and travel between them over the ocean on staggered 180-second routes. The bounded four-bird hunt population and existing falling/pickup recovery remain.

Recorded ocean, wood/gravel footsteps, rain and foliage audio remain context driven. Campfires and torches now add original cached, quiet spatial fire crackle that stops when extinguished. This fire bed is synthesized, not a field recording. Stair footsteps use the wooden-deck sound, and beach walking retains pooled fading sand footprints.

## Wildlife and models

Original boar, crab and sea turtle GLBs are generated offline by `tools/generate_wildlife_models.gd`. Their heads, snouts, tusks, hooves, shell scutes, flippers and jointed legs use natural proportions and muted materials. They are original modeled assets, not photographic scans. Equipment models use weathered shared wood/metal materials and physical-scale dimensions.

Each island gets at most four ground-checked animals: one boar, one turtle and two crabs. They wander within their territory, flee approaching players, stop roaming during rain and suspend active movement beyond 65 m. Boars retaliate when injured; nearby lit campfires repel their approach. Spear and bow damage work through real collision targets. Animals drop Raw Meat or Raw Crab; the Bonfire cooks these into Cooked Meat/Cooked Crab. Cooked food restores 45/28 hunger. Respawn takes 240 active seconds; health and remaining respawn timers are saved. The existing gulls, fish and sharks remain.

## Save and performance contracts

Optional `progression` metadata carries level, capped activity counters, tank equipment, oxygen, stamina, wetness and torch fuel. Optional `wildlife` carries stable island/index records. New machine built-piece `survival` dictionaries carry fuel, water, work, charge, enabled state and transmission count. Existing identifiers, building indexes 0–10, 30 inventory slots, rope-gun ownership, save version, island textures and once-per-save 2,000 supplies remain intact.

Machine simulation runs at 1 Hz; condition sampling at 4 Hz; animal decisions at about 7 Hz, with smooth nearby physics movement. Lights have no dynamic shadows and animal parts are merged offline. Source checks and desktop previews cannot establish Android frame rate, thermals or absence of every possible bug. No APK is exported by this update.

## Remaining design roadmap

The large pasted concept includes additional full systems: shifting terrain/caves, rivers/waterfalls, tides and whirlpools, every listed biome/species, boats with hull leaks and fuel maintenance, NPC survivors/trading, seasons/ecological populations, advanced injuries/infection/clothing/durability/spoilage, tracking, climbing ropes/zip lines, complete procedural story locations and full photogrammetry art replacement. Those are not supplied by this verified mission expansion and must not be advertised as playable yet.

## Latest cinematic and raft refinement

The opening is now narrated and lasts about 26 seconds, determined by the prerecorded spoken lines. It includes approach/impact effects and a two-second image-to-dawn gameplay handoff. Narration is locally synthesized with Microsoft David Desktop. Skip stops voices/effects immediately; Continue keeps the saved clock. The starter raft is now nine rounded weathered timbers with cross-poles, rope lashings and a decorative cloth mast. The display cloth has no navigation effect and is hidden when Sail Kit is installed. Foundation decks share the new detailed timber image. Saves, collisions, building supports and upgrade controls retain their existing formats.
