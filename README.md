# Dead Ship

A first-person science-fiction cleanup and spacecraft restoration simulator.
You are a contracted recovery technician: board a dead ship, scrub it, patch
it, and bring its systems back one at a time until it is a working vessel
again.

This repository holds the **first playable vertical slice**: one small
derelict, the *ICV Kestrel*, and one complete recovery contract.

- Engine: **Godot 4.4.1-stable** (standard build, GDScript, Forward+ renderer, Jolt physics)
- Target: desktop Windows (also runs on Linux/macOS from the editor)
- No external assets or plugins. Geometry is built from primitives, materials
  are procedural shaders, and all audio is synthesised at boot.

## Running it

1. Install [Godot 4.4.1-stable](https://godotengine.org/download/archive/4.4.1-stable/)
   (the standard build, not .NET). 4.4 is the minimum: the project uses the
   built-in Jolt physics engine introduced in that release.
2. Open the Godot Project Manager, choose **Import**, and select `project.godot`.
3. Press **F5** (Run Project). The main scene is `scenes/main.tscn`.

From a terminal:

```bash
godot --path .
```

A Windows export preset is included (`export_presets.cfg`); exporting needs
the 4.4.1 export templates installed through the editor.

## Controls

| Input | Zero-g | Gravity |
| --- | --- | --- |
| Mouse | Look | Look |
| W A S D | Thrust forward / left / back / right | Walk |
| Space / Ctrl | Thrust up / down | Jump / - |
| Shift | Stabilise: brake to a stop and re-level | Sprint |
| Z / C | Roll left / right | - |
| E | Interact, pick up, drop, seat a part (hold to crank doors) | same |
| Left mouse | Use equipped tool; throw the carried object | same |
| 1 / 2 / 3, wheel | Scrubber / Arc Sealer / Splicer | same |
| F | Suit lamp | same |
| Tab | Suit scan: marks everything still needing work and shows the task list | same |
| F1 / Esc | Toggle controls help / pause | same |

## The contract

The Kestrel is three compartments in a line: **Docking Airlock**, **Main
Corridor**, **Engineering**. She starts dark, airless and without gravity.

1. **Board.** The airlock is pressurised from your shuttle; the ship is in
   vacuum, so the inner door is held shut by the pressure difference. Pull the
   *Airlock Cycle* lever to pump the chamber down, then crank the door open.
2. **Repair the distribution panel** (Engineering, west wall). Splice both
   severed bus feeds with the Splicer, pull the burnt fuse, and seat the spare
   fuse cartridge that is drifting near the tipped spares bin.
3. **Restore power.** Close the main breaker. Lights come up outward from the
   panel, doors get their motors back, consoles wake.
4. **Seal the hull breach** (Engineering, east wall). Work the Arc Sealer
   around the rim; sealant creeps inward wherever you hold it.
5. **Repressurise.** Start the pumps at the *Life Support* console. Start them
   before sealing the breach and you can watch the air leave as fast as it
   arrives.
6. **Gravity.** Engage the field at the *Gravity Field* console. Everything
   that was floating comes down.
7. **Finish the job.** Splice the two corridor lighting junctions, feed junk to
   the *Waste Reclaim* hopper in the corridor, stow salvage in the locker in
   the airlock, and scrub every grime patch.
8. **File the report** at the contract terminal in the airlock.

Cleaning, hauling and the lighting repairs can be done at any point; the
system steps are ordered by the dependencies below.

## Ship systems

`ShipSystems` (`scripts/ship/ship_systems.gd`) holds explicit inputs (panel
repaired, breaker closed, pump switch, gravity switch, lighting faults) and
*derives* each system's state from them and from a small per-compartment
pressure simulation every physics tick.

| System | Needs | Why | What you see |
| --- | --- | --- | --- |
| Main power | Panel repaired, breaker closed | The breaker will not latch onto a faulted bus | Lights, door motors, live consoles, hum |
| Lighting | Power; each circuit's junction intact | Faulted circuits arc instead of conducting | Emergency red -> flicker -> steady |
| Atmosphere | Power for the pumps; an airtight hull | A breached compartment leaks faster than the pumps fill | Pressure readouts, venting at the breach, haze, sound opening up |
| Gravity | Power; 60 kPa in Engineering | The field coils are air-cooled, so an interlock holds them off in vacuum | Player walks, debris falls, generator rings spin |

Because states are derived rather than scripted, failures are consistent too:
open the breaker again and lights, pumps and gravity all drop out, and the
contract objectives un-tick.

Other interactions that fall out of the simulation:

- Doors will not open against more than 10 kPa of pressure difference, and
  open doors let compartments equalise.
- Air escaping through the breach drags loose objects toward it.
- Debris coasts indefinitely in vacuum and is slowed by drag once there is air.
- World audio is low-passed by ambient pressure: muffled in vacuum, clear at
  one atmosphere.

## Project layout

```
project.godot            Settings, input map, autoloads (Sfx, Game)
scenes/
  main.tscn              Entry point: instances ship + player + HUD
  player/player.tscn     CharacterBody3D, camera, suit lamp
  ships/kestrel.tscn     The Kestrel (root node + script; interior is built in code)
  ui/hud.tscn            HUD root
scripts/
  core/                  Game registry, Sfx library, AudioSynth, physics layers, main
  player/                Player controller, Interactor (raycast, carry), ToolBelt
  interaction/           Interactable: the reusable interaction component
  tools/                 Tool base class + Scrubber, Arc Sealer, Splicer
  props/                 GrimeSurface, Debris, DepositContainer, HullBreach,
                         RepairPoint, PartSocket, PowerPanel, LeverSwitch, ControlStation
  ship/                  Ship base, ShipSystems, Compartment, Door, ShipLight,
                         ShipKit (construction helpers), ShipMaterials
  ships/                 KestrelShip: layout, wiring and contract for this vessel
  contracts/             Contract, Objective
  ui/                    Hud
shaders/                 hull_panel, hazard, grime, breach
tests/                   Headless end-to-end smoke test
tools/                   Screenshot tour (developer tool)
```

### How the pieces fit

- **Interactable** is a plain `Node` component attached to any collider. It can
  expose an action on the interact key (tap or hold), tool work (`tool_id`,
  `progress`), and/or a socket for a carried item, plus the name and
  description shown when the player looks at it. Doors, levers, debris, grime,
  the breach and repair points all use it; none has custom input code.
- **Tool** owns only its view model and work feedback. The Interactor matches
  the equipped tool's `tool_id` to the target's and forwards the work, so a new
  tool is a small subclass plus `ToolBelt.add_tool()`.
- **Ship** is the base class for a vessel. A concrete ship overrides `_build()`
  and uses `add_compartment`, `add_door`, `add_light`, `add_grime`,
  `add_debris`, `add_breach`, ... to construct itself and define its contract.
  The base class turns system state changes into lighting, gravity, audio and
  environment changes. A second ship is a new script in `scripts/ships/` and a
  two-line scene; point `ship_scene` in `scenes/main.tscn` at it.
- **Contract** is an ordered list of `Objective`s, each polled through a
  callable, plus payout terms. It knows nothing about any particular ship.
- Gravity uses Godot's own mechanism: one `Area3D` over the interior overrides
  gravity for every rigid body inside it, so loose objects need no gravity code.

## Design decisions

- **Interiors are built in code from primitives** (`ShipKit`) rather than
  authored in the editor. It kept the slice consistent and verifiable in a
  session with no editor access. The cost is that the ship cannot be dressed
  visually in the editor yet; see next steps.
- **Grime is a painted mask.** Each patch is one quad with a small greyscale
  texture that the scrubber erases; a shader draws dirt wherever the mask is
  non-zero. Cleaning is incremental and cheap, and a patch finishes itself
  once 95% is gone so nobody hunts for the last speck.
- **Zero-g look uses a rollable reference frame**: yaw and pitch are measured
  against a frame that the roll keys rotate. That is full six-degree freedom
  without the slow roll drift of naive local-axis mouselook. Shift brakes and
  re-levels.
- **The body is a ball in zero-g and a capsule under gravity**, growing
  downward from the head when gravity returns so the view never jumps.
- **The airlock is powered by the player's shuttle**, so the game opens in a
  small lit room and the door opens onto the dark.
- **Waste hoppers accept salvage too** (it is scrapped for no payout); the
  salvage locker rejects junk. The spare fuse is rejected by both, so the
  contract cannot be soft-locked by throwing it away.

## Testing

End-to-end smoke test (no display needed). It boots the real game scene and
plays the entire contract through the same components the player uses,
including movement driven through the input map:

```bash
godot --headless --fixed-fps 60 --path . res://tests/smoke_test.tscn
```

Exit code 0 means every check passed. On a fresh clone, run
`godot --headless --path . --import` once first so the script class cache exists.

Screenshot tour (needs a display; use `xvfb-run` on a headless machine):

```bash
godot --path . res://tools/capture_tour.tscn -- --out=/tmp/tour
```

## Status

Verified in this repository with Godot 4.4.1 on Linux: scripts compile, the
smoke test passes (75 checks), and the screenshot tour was rendered and
reviewed with the Forward+ renderer on a software Vulkan driver.

| Area | State |
| --- | --- |
| Zero-g and walking movement, mode switching | Implemented, covered by the smoke test |
| Interaction, carrying, throwing, tools | Implemented, covered by the smoke test |
| Scrubbing, debris and salvage disposal | Implemented, covered by the smoke test |
| Electrical repair, hull sealing | Implemented, covered by the smoke test |
| Power, lighting, atmosphere, gravity and their dependencies | Implemented, covered by the smoke test |
| Contract objectives, sign-off, payout screen | Implemented, covered by the smoke test |
| Lighting, materials, derelict vs. restored look | Implemented, reviewed from rendered screenshots |
| HUD | Implemented, reviewed from screenshots |

Not verified here, because it needs a person at a real machine:

- **Game feel.** Mouse sensitivity, thruster acceleration and drag, carry
  stiffness, scrub and seal rates, and hold times are first-pass numbers that
  have never been played by hand. All are exported or constant values at the
  top of their scripts.
- **Audio.** The test environment has no audio device. The synthesised sounds
  generate and play without errors but nobody has listened to them; levels and
  timbre will need tuning.
- **Performance and look on real GPUs.** Screenshots came from a CPU
  rasteriser at 960x540. Frame rate, shadow quality, glow and volumetric haze
  on actual Windows hardware are unmeasured.
- **Windows itself.** Nothing was run or exported on Windows.

Known limitations:

- Godot prints `ObjectDB instances leaked at exit` when quitting. It is the
  looping audio players (suit hum, thrusters, breach hiss) still being active
  as the engine shuts down; it is harmless.
- On machines without Vulkan, Godot falls back to its OpenGL renderer. The
  game runs there (checked from screenshots) but without ambient occlusion or
  volumetric haze.
- No settings menu, key rebinding UI, save data or gamepad support.
- Tool view models can clip into walls at very close range.
- Console readouts use the engine's default font and are small at a distance.
- One ship, one contract. No economy, upgrades or hazards beyond the breach.

## Next steps

1. **Hands-on tuning pass on Windows**: movement, tool rates, audio levels,
   lighting and performance, with the numbers above adjusted from real play.
2. **Move ship authoring into the editor**: turn the `ShipKit` pieces and
   props into scenes/`@tool` nodes so interiors can be laid out and dressed
   visually, keeping `Ship`'s registration API.
3. **A second, larger vessel and contract** to prove the architecture: several
   pressure zones, more than one breach, a longer repair procedure, and
   salvage value feeding a first persistent upgrade.
