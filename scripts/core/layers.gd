class_name Layers
## Physics layer bit values. Names mirror `layer_names/3d_physics` in project.godot.

const WORLD := 1      ## Static ship geometry and doors.
const PROPS := 2      ## Loose rigid bodies (debris, salvage, parts).
const INTERACT := 4   ## Ray-only targets: grime, repair points, breaches.
const PLAYER := 8
