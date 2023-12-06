package main

import "core:fmt"
import "core:mem"
import "core:math"
import "core:time"
import rl "vendor:raylib"
import "sprites"

LEVEL_FILE :: "assets/levels/first.level"
frame_count : f32

Player :: struct {
    rect: rl.Rectangle,
    vel: rl.Vector2,
    is_grounded: bool,

    facing_dir: Direction,
    anim: ^sprites.AnimationSystem(PlayerAnimation),
}

PlayerAnimation :: enum u8 {
    Idle, Walk, Jump,        // Sidescroller
    Forward, Back, Right,    // TopDown
}

PLAYER_ANIMATIONS := [PlayerAnimation]sprites.Animation{
    .Idle = {    start_tile = 0,  end_tile = 2,  duration = 2 },
    .Walk = {    start_tile = 3,  end_tile = 11, duration = 1 },
    .Jump = {    start_tile = 12, end_tile = 15, duration = 0.5 * JUMP_APEX_TIME },

    .Forward = { start_tile = 16, end_tile = 19, duration = 2},
    .Back    = { start_tile = 20, end_tile = 23, duration = 2},
    .Right   = { start_tile = 24, end_tile = 24, duration = 2},
}

Direction :: enum { North, East, South, West, }

player_pos :: proc(player: Player) -> rl.Vector2 {
    return {player.rect.x, player.rect.y}
}

PLAYER_SIZE :: 16
PLAYER_SIZE_V :: rl.Vector2{PLAYER_SIZE, PLAYER_SIZE}

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }
    defer free_all(context.temp_allocator)

    DEFAULT_SCREEN :: rl.Vector2{1600, 900}
    world := World{
        screen = DEFAULT_SCREEN,
        cam = { zoom = 4.75, offset = DEFAULT_SCREEN * 0.5 },
        mode = .TopDown,
        player = {
            rect = { width = PLAYER_SIZE, height = PLAYER_SIZE },
            // rect = { x = 1446, y = -159, height = PLAYER_SIZE, width = PLAYER_SIZE },
        },
    }
    reserve(&world.boxes, 1024)
    reserve(&world.checkpoint.boxes, 1024)
    reserve(&world.checkpoint.activated, 64)
    defer {
        delete(world.boxes)
        delete(world.checkpoint.boxes)
        delete(world.checkpoint.activated)
    }

    config_load(LEVEL_FILE, &world)

    rl.SetTraceLogLevel(.ALL if ODIN_DEBUG else .WARNING)
    rl.InitWindow(i32(world.screen.x), i32(world.screen.y), "Dunkey game")
    defer rl.CloseWindow()

    world.tex_atlas = {
        tile_size = 16,
        texture = rl.LoadTexture("assets/Environment.png"),
    }
    defer rl.UnloadTexture(world.tex_atlas.texture)

    world.player.anim = &sprites.AnimationSystem(PlayerAnimation){
        animations = PLAYER_ANIMATIONS,
        atlas = {
            tile_size = 16,
            texture = rl.LoadTexture("assets/player.png"),
        },
    }
    defer rl.UnloadTexture(world.player.anim.atlas.texture)
    // @HACK: need to switch animations to initialize it properly
    sprites.play(world.player.anim, PlayerAnimation.Walk)
    sprites.play(world.player.anim, PlayerAnimation.Forward)

    rl.SetTargetFPS(60)
    for !rl.WindowShouldClose() {
        dt := rl.GetFrameTime()
        frame_count += 1

        when ODIN_DEBUG {
            gui_update(&world, dt)
            if world.gui.is_dragging {
                dt = 0
            }
        }

        time.stopwatch_start(&world.timers.total)

        input := get_input(world)
        update(&world, input, dt)

        time.stopwatch_start(&world.timers.draw)
        draw(world)
        time.stopwatch_stop(&world.timers.draw)

        free_all(context.temp_allocator)
        time.stopwatch_stop(&world.timers.total)
    }
}

draw :: proc(w: World) {
    rl.BeginDrawing()
    defer rl.EndDrawing()

    rl.ClearBackground(rl.GRAY if w.mode == .Sidescroller else rl.ORANGE)

    rl.BeginMode2D(w.cam)

    // First draw background boxes.
    for box in w.boxes do if box.type != .Portal && w.mode not_in box.mode {
        color := box_color(box.mode)
        rl.DrawRectangleRec(box.rect, color)
    }

    // Draw drop-shadows under foreground boxes.
    for box in w.boxes do if w.mode in box.mode {
        if box.type != .Wall && box.type != .Push {
            continue
        }
        OFFSET :: 2
        shadow := rl.Rectangle{
            box.rect.x + OFFSET, box.rect.y + OFFSET,
            box.rect.width, box.rect.height,
        }
        rl.DrawRectangleRec(shadow, {0, 0, 0, 150})
    }

    for box in w.boxes do if w.mode in box.mode {
        // @TODO: cull off-screen boxes

        switch box.type {
        case .Checkpoint:
            when ODIN_DEBUG do if !w.gui.hide_grid {
                rl.DrawRectangleRec(box.rect, rl.YELLOW)
            }
        case .Wall:
            color := box_color(box.mode)
            rl.DrawRectangleRec(box.rect, color)
        case .Push:
            rect := sprites.sprite(w.tex_atlas, 4)
            rl.DrawTextureRec(w.tex_atlas.texture, rect, {box.rect.x, box.rect.y}, rl.WHITE)
        case .Spike:
            // @TODO: spike orientation
            rect := sprites.sprite(w.tex_atlas, 8)
            rl.DrawTextureRec(w.tex_atlas.texture, rect, {box.rect.x, box.rect.y}, rl.WHITE)
        case .Portal:
            if w.mode in box.mode {
                rect := sprites.sprite(w.tex_atlas, 0)
                // Rotate portals around their midpoints.
                midpoint := rl.Rectangle{
                    box.rect.x + box.rect.width / 2,
                    box.rect.y + box.rect.height / 2,
                    box.rect.width, box.rect.height,
                }
                rot_origin := rl.Vector2{midpoint.width / 2, midpoint.height / 2}
                rl.DrawTexturePro(w.tex_atlas.texture, rect, midpoint, rot_origin, frame_count, rl.WHITE)
            }
        }
    }

    player_sprite := sprites.animation_rect(w.player.anim)
    if w.player.vel.x < 0 {
        player_sprite.width *= -1
    }
    rl.DrawTextureRec(w.player.anim.atlas.texture, player_sprite, player_pos(w.player), rl.WHITE)

    when ODIN_DEBUG{
        gui_draw2d(w)
    }
    rl.EndMode2D()

    when ODIN_DEBUG {
        gui_draw(w)
    }
}

draw_text :: proc(x, y, font_size: i32, format: string, args: ..any) {
    str := fmt.ctprintf(format, ..args)
    rl.DrawText(str, x, y, font_size, rl.DARKBLUE)
}

box_color :: proc(mode: bit_set[GameMode]) -> rl.Color {
    switch mode {
        case {.Sidescroller, .TopDown}: return rl.PURPLE
        case {.Sidescroller}:           return rl.BLUE
        case {.TopDown}:                return rl.RED
    }

    panic("box_color called on Box with empty bit_set[GameMode]")
}