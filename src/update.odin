package main

import rl "vendor:raylib"
import "core:math"
import "core:math/linalg"
import "core:fmt"
import "core:time"
import "sprites"

EPSILON :: 0.0001
GRAVITY :: 500
FRICTION :: 0.1
#assert(FRICTION >= 0 && FRICTION <= 1)


PLAYER_SPEED :: f32(500.0)
JUMP_FORCE :: 500
JUMP_APEX_TIME :: JUMP_FORCE / GRAVITY

Input :: enum u8 {
    Up, Down,
    Left, Right,
    Jump,
    ChangeMode,
    ReloadCheckpoint,
}

get_input :: proc(w: World) -> (input: bit_set[Input]) {
    if w.mode == .Sidescroller && (rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W)) {
        input += {.Jump}
    }

         if rl.IsKeyDown(.UP)    || rl.IsKeyDown(.W) do input += {.Up}
    else if rl.IsKeyDown(.DOWN)  || rl.IsKeyDown(.S) do input += {.Down}
         if rl.IsKeyDown(.LEFT)  || rl.IsKeyDown(.A) do input += {.Left}
    else if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) do input += {.Right}

    if rl.IsKeyPressed(.R) do input += {.ReloadCheckpoint}

    when ODIN_DEBUG {
        if rl.IsKeyPressed(.SPACE) do input += {.ChangeMode}
    }

    return input
}

update :: proc(w: ^World, input: bit_set[Input], dt: f32) {
    if .ChangeMode in input {
        change_game_mode(w)
    }

    if .ReloadCheckpoint in input {
        checkpoint_reload(w)
    }

    switch w.mode {
        case .Sidescroller: sidescroll_update(w, input, dt)
        case .TopDown     : top_down_update(w, input, dt)
    }

    when ODIN_DEBUG {
        time.stopwatch_start(&w.timers.physics)
        defer time.stopwatch_stop(&w.timers.physics)
    }

    subupdate(w, input, dt)
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
    for &box, box_id in w.boxes do if w.mode in box.mode {
        collision := swept_rect_collision(w.player.rect, box.rect, w.player.vel, dt) or_continue

        switch box.type {
        case .Checkpoint: checkpoint_activate(w, box_id)
        case .Portal: change_game_mode(w)
        case .Spike:
            if collision.normal.y == -1 {
                checkpoint_reload(w) // @TODO: play death animation
                return
            }
            fallthrough
        case .Wall:
            delta_vel := collision.normal * linalg.abs(w.player.vel) * (1 - collision.time_entry)
            w.player.vel += delta_vel
            if collision.normal.y == -1 {
                w.player.is_grounded = true
            }

        case .Push:
            delta_v := collision.normal * PLAYER_SIZE_V
            if collision.normal.y == -1 {
                w.player.is_grounded = true
            }

            box.rect.x -= delta_v.x
            box.rect.y -= delta_v.y
            for wall, wall_id in w.boxes do if wall.type == .Wall || wall.type == .Push {
                if box_id == wall_id { continue }
                if rl.CheckCollisionRecs(box.rect, wall.rect) {
                    box.rect.x += delta_v.x
                    box.rect.y += delta_v.y

                    w.player.vel += collision.normal * linalg.abs(w.player.vel) * (1 - collision.time_entry)
                }
            }
        }
    }

    // Apply player velocity
    w.player.rect.x += w.player.vel.x * dt
    w.player.rect.y += w.player.vel.y * dt

    sprites.update(w.player.anim, dt)
}

sidescroll_update :: proc(w: ^World, input: bit_set[Input], dt: f32) {
    has_move_input := .Left in input || .Right in input
    p_anim := w.player.anim

    if w.player.vel == {0, 0} || (p_anim.current_anim == .Walk && !has_move_input) {
        sprites.play(p_anim, PlayerAnimation.Idle)
    } else if w.player.is_grounded && has_move_input {
        sprites.play(p_anim, PlayerAnimation.Walk)
    } else if w.player.is_grounded {
        sprites.play(w.player.anim, PlayerAnimation.Idle)
    }

         if .Left  in input do w.player.vel.x -= PLAYER_SPEED * dt
    else if .Right in input do w.player.vel.x += PLAYER_SPEED * dt


    w.player.vel.y += GRAVITY * dt
    if w.player.is_grounded {
        if .Jump in input {
            w.player.is_grounded = false
            w.player.vel.y = -JUMP_FORCE
            apex_time := abs(w.player.vel.y / GRAVITY)
            sprites.play(p_anim, PlayerAnimation.Jump)
            rl.PlaySound(w.sounds[.Jump])
        }
    }
}

top_down_update :: proc(w: ^World, input: bit_set[Input], dt: f32) {
    acc := PLAYER_SPEED * dt
    if .Up in input {
        w.player.vel.y -= acc
        w.player.facing_dir = .North
        sprites.play(w.player.anim, PlayerAnimation.Back)
    } else if .Down in input {
        w.player.vel.y += acc
        w.player.facing_dir = .South
        sprites.play(w.player.anim, PlayerAnimation.Forward)
    }

    if .Left in input {
        w.player.vel.x -= acc
        w.player.facing_dir = .West
        sprites.play(w.player.anim, PlayerAnimation.Right)
    } else if .Right in input {
        w.player.vel.x += acc
        w.player.facing_dir = .East
        sprites.play(w.player.anim, PlayerAnimation.Right)
    }
}

Collision :: struct {
    time_entry: f32,
    point, normal: rl.Vector2,
}

ray_vs_rect :: proc(origin, dir: rl.Vector2, rect: rl.Rectangle) -> (Collision, bool) {
    rect_pos  := rl.Vector2{rect.x, rect.y}
    rect_size := rl.Vector2{rect.width, rect.height}

    inv_dir := 1.0 / dir // Cached

    // Time of entry and exit collisions.
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

    contact_normal : rl.Vector2
    if t_near.x > t_near.y {
        contact_normal = {1, 0} if inv_dir.x < 0 else {-1, 0}
    } else if t_near.x < t_near.y {
        contact_normal = {0, 1} if inv_dir.y < 0 else {0, -1}
    } // else contact_normal is {0, 0}

    return {
        time_entry = t_hit_near,
        normal = contact_normal,
        point = origin + t_hit_near * dir,
    }, true
}

// Returns the time of impact between the player and a rectangle.
// Move player by velocity * collision_time to avoid penetration.
swept_rect_collision :: proc(obj, obstacle: rl.Rectangle, vel: rl.Vector2, dt: f32) -> (Collision, bool) {
    if vel == {0, 0} {
        return {}, false
    }

    // @TODO: Move padding out of this function, this is player specific.
    PADDING :: 2.0
    p_pos  := rl.Vector2{obj.x + PADDING / 2, obj.y + PADDING / 2}
    p_size := rl.Vector2{obj.width - PADDING, obj.height - PADDING}

    expanded_rect := rl.Rectangle{
        x = obstacle.x - (p_size.x / 2),
        y = obstacle.y - (p_size.y / 2),
        width  = obstacle.width  + p_size.x,
        height = obstacle.height + p_size.y,
    }

    collision, ok := ray_vs_rect(p_pos + p_size / 2, vel * dt, expanded_rect)
    return collision, ok && collision.time_entry >= 0 && collision.time_entry < 1
}

change_game_mode :: proc(w: ^World) {
    w.mode = inverse_mode(w.mode)

    anim: PlayerAnimation = .Forward if w.mode == .TopDown else .Idle
    sprites.play(w.player.anim, anim)
    rl.PlaySound(w.sounds[.PortalEnter])
}