package main

import rlib "vendor:raylib"
import "core:math"
import "core:math/linalg"
import "core:fmt"
import "sprites"

EPSILON :: 0.0001
GRAVITY :: 1000
FRICTION :: 0.25
#assert(FRICTION >= 0 && FRICTION <= 1)

FIXED_DT :: 1.0 / 120

PLAYER_SPEED :: f32(1000.0)
JUMP_FORCE :: 1000

Input :: enum u8 {
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
        if w.mode == .TopDown {
            w.mode = .Sidescroller
            sprites.play(w.player.animation_system, "idle", 2)
        } else {
            w.mode = .TopDown
            sprites.play(w.player.animation_system, "forward", 2)
        }
    }

    switch w.mode {
        case .Sidescroller: sidescroll_update(w, input, dt)
        case .TopDown     : top_down_update(w, input, dt)
    }

    w.dt_acc += dt
    for w.dt_acc >= FIXED_DT {
        subupdate(w, input, FIXED_DT)
        w.dt_acc -= FIXED_DT
    }
}

subupdate :: proc(w: ^World, input: bit_set[Input], dt: f32) {
    // Camera smoothly follows player.
    p_pos := player_pos(w.player)
    if linalg.distance(p_pos, w.cam.target) > 5  {
        w.cam.target += (p_pos - w.cam.target) * 0.9 * dt
    }

    if abs(w.player.vel.y) < EPSILON do w.player.vel.y = 0
    if abs(w.player.vel.x) < EPSILON do w.player.vel.x = 0

    if w.player.vel.y != 0 {
        w.player.is_grounded = false
    }

    w.player.vel *= 1 - FRICTION

    // Resolve box collisions.
    for box in w.boxes do if w.mode in box.mode {
        collision, ok := swept_rect_collision(w.player, box.rect, dt)
        if !ok {
            continue
        }

        w.player.vel += collision.normal * linalg.abs(w.player.vel) * (1 - collision.time_entry)
        if collision.normal.y == -1 {
            w.player.is_grounded = true
        }
    }

    // Apply player velocity
    w.player.rect.x += w.player.vel.x * dt
    w.player.rect.y += w.player.vel.y * dt

    sprites.update(w.player.animation_system, dt)
}

sidescroll_update :: proc(w: ^World, input: bit_set[Input], dt: f32) {
    has_move_input := .Left in input || .Right in input
    p_anim := w.player.animation_system

    if w.player.vel == {0, 0} || (p_anim.current_anim == "walk" && !has_move_input) {
        sprites.play(p_anim, "idle", 2)
    } else if w.player.is_grounded && has_move_input {
        sprites.play(p_anim, "walk", 1)
    } else {
        // sprites.stop(w.player.animation_system)
        // sprites.play(w.player.animation_system, "walk", 1)
    }

         if .Left  in input do w.player.vel.x -= PLAYER_SPEED * dt
    else if .Right in input do w.player.vel.x += PLAYER_SPEED * dt


    w.player.vel.y += GRAVITY * dt
    if w.player.is_grounded {
        if .Up in input {
            w.player.is_grounded = false
            w.player.vel.y = -JUMP_FORCE
            apex_time := abs(w.player.vel.y / GRAVITY)
            fmt.println("apex", apex_time)
            sprites.play(p_anim, "jump", apex_time) // @TODO: calculate jump time
        }
    }
}

top_down_update :: proc(w: ^World, input: bit_set[Input], dt: f32) {
    acc := PLAYER_SPEED * dt
    if .Up in input {
        w.player.vel.y -= acc
        w.player.facing_dir = .North
    } else if .Down in input {
        w.player.vel.y += acc
        w.player.facing_dir = .South
    }

    if .Left in input {
        w.player.vel.x -= acc
        w.player.facing_dir = .West
    } else if .Right in input {
        w.player.vel.x += acc
        w.player.facing_dir = .East
    }

    sprites.play(w.player.animation_system, "forward", 1)
}

Collision :: struct {
    time_entry: f32,
    point, normal: rlib.Vector2,
}

ray_vs_rect :: proc(origin, dir: rlib.Vector2, rect: rlib.Rectangle) -> (Collision, bool) {
    inv_dir := 1.0 / dir

    rect_pos  := rlib.Vector2{rect.x, rect.y}
    rect_size := rlib.Vector2{rect.width, rect.height}


    t_near := (rect_pos - origin) * inv_dir
    t_far  := (rect_pos + rect_size - origin) * inv_dir
    if math.is_nan(t_near.x) || math.is_nan(t_near.y) do return {}, false
    if math.is_nan(t_far.x)  || math.is_nan(t_far.y)  do return {}, false

    // Normalize them
    if t_near.x > t_far.x {
        t_near.x, t_far.x = t_far.x, t_near.x
    }
    if t_near.y > t_far.y {
        t_near.y, t_far.y = t_far.y, t_near.y
    }

    if t_near.x > t_far.y || t_near.y > t_far.x {
        return {}, false
    }

    t_hit_near := max(t_near.x, t_near.y)
    t_hit_far  := min(t_far.x, t_far.y)

    if t_hit_far < 0 {
        return {}, false // Ray pointing away from rect.
    }

    contact_normal : rlib.Vector2
    if t_near.x > t_near.y {
        contact_normal = {1, 0} if inv_dir.x < 0 else {-1, 0}
    } else if t_near.x < t_near.y {
        contact_normal = {0, 1} if inv_dir.y < 0 else {0, -1}
    }

    return {
        time_entry = t_hit_near,
        normal = contact_normal,
        point = origin + t_hit_near * dir,
    }, true
}

// Returns the time of impact between the player and a rectangle.
// Move player by velocity * collision_time to avoid penetration.
swept_rect_collision :: proc(player: Player, rect: rlib.Rectangle, dt: f32) -> (Collision, bool) {
    if player.vel == {0, 0} {
        return {}, false
    }

    expanded_rect := rlib.Rectangle{
        x = rect.x - (player.rect.width  / 2),
        y = rect.y - (player.rect.height / 2),
        width  = rect.width  + player.rect.width,
        height = rect.height + player.rect.height,
    }

    p_pos  := rlib.Vector2{player.rect.x, player.rect.y}
    p_size := rlib.Vector2{player.rect.width, player.rect.height}
    collision, ok := ray_vs_rect(p_pos + p_size / 2, player.vel * dt, expanded_rect)
    return collision, ok && collision.time_entry >= 0 && collision.time_entry < 1
}