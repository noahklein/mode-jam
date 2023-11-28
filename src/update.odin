package main

import rlib "vendor:raylib"
import "core:math/linalg"
import "core:fmt"

FRICTION :: 0.25
#assert(FRICTION >= 0 && FRICTION <= 1)

GRAVITY :: -30

PLAYER_SPEED :: f32(50.0)
JUMP_FORCE :: 30

Input :: enum {
    Up, Down,
    Left, Right,
    ChangeMode,
}

get_input :: proc() -> (input: bit_set[Input]) {
         if rlib.IsKeyDown(.UP)    || rlib.IsKeyDown(.W) do input += {.Up}
    else if rlib.IsKeyDown(.DOWN)  || rlib.IsKeyDown(.S) do input += {.Down}
         if rlib.IsKeyDown(.LEFT)  || rlib.IsKeyDown(.A) do input += {.Left}
    else if rlib.IsKeyDown(.RIGHT) || rlib.IsKeyDown(.D) do input += {.Right}

    if rlib.IsKeyPressed(.SPACE) do input += {.ChangeMode}

    return input
}

update :: proc(w: ^World, input: bit_set[Input], dt: f32) {
    if .ChangeMode in input {
        w.mode = .Sidescroller if w.mode == .TopDown else .TopDown
    }

    // Camera smoothly follows player.
    CAM_SMOOTH_MIN_DISTANCE :: 15
    CAM_SMOOTH_MIN_SPEED :: 5
    CAM_SMOOTH_FRACTION_SPEED :: 0.8
    player_pos := rlib.Vector2{w.player.rect.x, w.player.rect.y}
    diff := player_pos - w.cam.target
    length := linalg.length(diff)
    if length > CAM_SMOOTH_MIN_DISTANCE {
        speed := max(CAM_SMOOTH_FRACTION_SPEED * length, CAM_SMOOTH_MIN_SPEED)
        w.cam.target += diff * (speed * dt / length)
    }


    switch w.mode {
        case .Sidescroller: sidescroll_update(w, input, dt)
        case .TopDown     : top_down_update(w, input, dt)
    }

    // Apply forces
    w.player.vel *= 1 - FRICTION
    w.player.rect.x += w.player.vel.x * dt
    w.player.rect.y += w.player.vel.y * dt


    // Collision detection
    for box in w.boxes {
        if w.mode not_in box.mode {
            continue
        }

        if !rlib.CheckCollisionRecs(w.player.rect, box.rect) {
            continue
        }
        collision := rlib.GetCollisionRec(w.player.rect, box.rect)

    }
}

sidescroll_update :: proc(w: ^World, input: bit_set[Input], dt: f32) {
         if .Left  in input do w.player.vel.x -= PLAYER_SPEED
    else if .Right in input do w.player.vel.x += PLAYER_SPEED

    if w.player.is_grounded {
        w.player.vel.y = 0
        if .Up in input {
            w.player.is_grounded = false
            w.player.vel.y = JUMP_FORCE
        }
    } else {
        w.player.vel.y -= GRAVITY
    }
}

top_down_update :: proc(w: ^World, input: bit_set[Input], dt: f32) {
    acc := PLAYER_SPEED
    if .Up in input {
        w.player.vel.y -= acc
    } else if .Down in input {
        w.player.vel.y += acc
    }

    if .Left in input {
        w.player.vel.x -= acc
    } else if .Right in input {
        w.player.vel.x += acc
    }

}