package main

import "core:fmt"
import "core:time"
import rl "vendor:raylib"

import "sprites"

GameMode :: enum u8 { Sidescroller, TopDown }

World :: struct {
    mode: GameMode,
    screen: rl.Vector2,
    cam : rl.Camera2D,
    player: Player,
    boxes: [dynamic]Box,
    checkpoint: Checkpoint,

    tex_atlas: sprites.Atlas,
    sounds: [SoundId]rl.Sound,
    gui: Gui,

    timers: EngineTimers,
}

SoundId :: enum {
    PortalEnter, Jump,
}

Checkpoint :: struct {
    // Box ids of activated checkpoints, last is most recent.
    activated: [dynamic]int,

    // Snapshots of world properties.
    mode: GameMode,
    player: Player,
    boxes: [dynamic]Box,
}

checkpoint_activate :: proc(w: ^World, box_id: int) {
    #reverse for cp in w.checkpoint.activated {
        if cp == box_id {
            return // Already activated.
        }
    }
    append(&w.checkpoint.activated, box_id)

    // Save snapshot.
    w.checkpoint.mode = w.mode
    w.checkpoint.player = w.player

    clear(&w.checkpoint.boxes)
    for box in w.boxes {
        append(&w.checkpoint.boxes, box)
    }
}

checkpoint_reload :: proc(w: ^World) {
    if len(w.checkpoint.activated) == 0 {
        return // No checkpoints yet.
    }

    w.mode = w.checkpoint.mode
    w.player = w.checkpoint.player
    switch w.mode {
    case .Sidescroller: sprites.play(w.player.anim, PlayerAnimation.Walk)
    case .TopDown:      sprites.play(w.player.anim, PlayerAnimation.Forward)
    }
    clear(&w.boxes)
    for box in w.checkpoint.boxes {
        append(&w.boxes, box)
    }
}

EngineTimers :: struct {
    total, physics, draw: time.Stopwatch
}

stats_physics_pct :: proc(timers: EngineTimers) -> f64{
    return 100 * f64(dur(timers.physics)) / f64(dur(timers.total))
}

stats_draw_pct :: proc(timers: EngineTimers) -> f64{
    return 100 * f64(dur(timers.draw)) / f64(dur(timers.total))
}

dur :: #force_inline proc(sw: time.Stopwatch) -> time.Duration {
    return time.stopwatch_duration(sw)
}