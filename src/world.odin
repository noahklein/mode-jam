package main

import "core:fmt"
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
    gui: Gui,

    dt_acc: f32, // For fixed update
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
    for cp in w.checkpoint.activated {
        if cp == box_id {
            fmt.println("already activated")
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
    clear(&w.boxes)
    for box in w.checkpoint.boxes {
        append(&w.boxes, box)
    }
}