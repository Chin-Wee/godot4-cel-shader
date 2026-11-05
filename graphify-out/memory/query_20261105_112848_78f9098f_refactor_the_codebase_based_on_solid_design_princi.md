---
type: "query"
date: "2026-11-05T11:28:48.653706+00:00"
question: "refactor the codebase based on solid design principles."
contributor: "graphify"
outcome: "useful"
source_nodes: ["Aerial rendering study — DELIVERY MUST COMPLETE", "Base Materials"]
---

# Q: refactor the codebase based on solid design principles.

## Answer

Expanded from graph vocabulary: aerial flight control pose rendering materials. Audited first-party src, aerial, actor, scripts, shaders and authoring code. Source refactor integrated as 6878170: aerial_demo.tscn composes native Lighting, FlightCamera and FlightHUD owners; runtime camera, palette/weather/material state and HUD no longer live on the scene coordinator. mech_assets.gd statically prepares local imported animations/materials, while mech_character.gd retains movement-facing playback. flight_input.gd owns InputMap, sampling and platform events; flight_controller.gd consumes command data without global Input dependency. Five small cel shader wrappers share cel-material.gdshaderinc, preserving paint/saturation policies and template height mapping. Existing pose, cloud, bounded VFX, geometry, grass and compositor owners were retained after source review because they are already cohesive. Corrected stale native capture fixtures for seeded trails and visible inner flare. All 24 headless runs and shared-copy checks passed on feature branch and main. Six native shader renders are pixel-identical to baseline; aerial sunset/day references differ by 6/9 color bytes. Native lighting including scene reload, full aerial captures, pose preview and both-camera acrobatics/research replays pass. See REFACTOR_PLAN.md for scope, ownership and evidence. Installed Graphify does not index GDScript; source and behavior checks are authoritative.

## Outcome

- Signal: useful

## Source Nodes

- Aerial rendering study — DELIVERY MUST COMPLETE
- Base Materials