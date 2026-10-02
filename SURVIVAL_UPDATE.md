# After the Deluge — survival expansion

Run the project in Godot 4.7.1. Start a New Game to see the 18-second skippable earthquake/sinking-island opening. Existing saves continue without replaying it.

## Play

- **J / SURVIVAL button** opens the scrollable journal, recipes, construction shortcuts and actions. **H** hunts with a bow and arrows, or a spear when no loaded bow is available. Existing movement, swimming, collection and construction controls remain unchanged.
- Collect drifting debris. Building now consumes materials. The journal offers bonfire and planter shortcuts; aim at a free raft/foundation top socket and use the existing placement control.
- Craft a fishing rod, face open water from shore or the raft and cast. Stay within 3 metres for 8–15 seconds. Hunt fish underwater, birds overhead and boars on the outlying islands. Sharks attack swimmers; boars defend themselves at close range.
- Cook fish or meat near a bonfire with one wood. Cooking takes 12 seconds and waits if the bag is full. Use the journal to eat cooked food or coconuts.
- Craft a flask; fill it at the original island's freshwater pond, or distill seawater at a raft bonfire using two wood. Ocean water is never directly drinkable.
- Dive to submerged island terrain and collect sand within 3 metres. Air lasts about 20 seconds; resurface to recover. Smelt 3 sand with 2 wood at a bonfire to make glass.
- Convert fruit or potatoes to seeds. Build a suitable planter and use E to plant. Planted crop stage, growth progress, health and fruit timers are included in structure saves.
- Swim to **Palm Refuge (110, -100)**, **Iron Cay (-130, -160)** and **Last Signal (180, 120)**. The coordinates are world X/Z. Collect ore near dark rocks using the journal.
- Explore all three islands, craft a **Signal Beacon** (8 metal, 3 glass, 3 rope), and activate it at Last Signal to complete the rescue objective. You can continue playing afterward.

## Audio and resources

Ocean ambience, footsteps, swimming splashes, bird calls, crafting/impact sounds, bow release, earthquake rumble and a rescue cue are synthesized locally. The journal has a mute control. New terrain and animal geometry is original procedural content; existing palm models are reused. No paid assets or downloads were added. See SURVIVAL_ASSETS.md for the original additions' license and the pre-existing asset licensing boundary.

## Saving

Existing inventory and structure saves also store health/food/water, player position, story completion, island discoveries, ore depletion, sand depletion and in-progress cooking. Wildlife populations are recreated on load and replenished while exploring. The forgiving death rule returns the player to the raft with restored needs and retained supplies.

## Validation completed

- Godot script loading.
- Transactional crafting: success, insufficient ingredients, full-bag rollback and freed-slot reuse.
- Main-scene integration: opening completion and return of control, generated-island surface collision, all three discoveries, rescue completion, campaign state serialization, journal/mute controls, crop snapshots and inclusion in structure saves, bonfire availability and valid raft placement, timed cooking output.
- Desktop rendered inspection of the new island and journal at 960×640 in the Compatibility renderer. Existing project renderer settings were not changed.

The final integration run passed without script errors. Godot reported six ObjectDB instances at shutdown of the test harness; long-session memory behavior has not been established.

## Honest remaining limits

This is an expanded playable prototype with a rescue objective, not a release-quality realistic simulation. Animals and new islands are stylized, hunting loot enters inventory directly, fishing is a timed action, and the opening is a scripted scene rather than a globally simulated catastrophe. The raft still uses the existing buoyancy system and has no sailing/navigation system. There is no physical rescue ship or additional survivor story. Wildlife does not persist individually. New islands use simple terrain and do not share the original island's detailed shoreline shader effects. Full sound mixing/listening QA, gameplay balance, long-session stability, phone/touch layouts, performance across devices, and commercial redistribution rights for pre-existing assets remain unverified. The APK has not been rebuilt.
