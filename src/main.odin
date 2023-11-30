package main

import "core:fmt"
import "core:mem"
import rlib "vendor:raylib"
import "sprites"

GameMode :: enum u8 {
    Sidescroller,
    TopDown,
}

World :: struct {
    mode: GameMode,
    screen: rlib.Vector2,
    cam : rlib.Camera2D,
    player: Player,
    boxes: [dynamic]Box,

    tex_atlas: sprites.Atlas,

    dt_acc: f32, // For fixed update

    gui: Gui,
}

Player :: struct {
    rect: rlib.Rectangle,
    vel: rlib.Vector2,
    is_grounded: bool,

    facing_dir: Direction,
    animation_system: ^sprites.AnimationSystem,
}

Direction :: enum { North, East, South, West, }

player_pos :: proc(player: Player) -> rlib.Vector2 {
    return {player.rect.x, player.rect.y}
}

PLAYER_SIZE :: 16

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

    DEFAULT_SCREEN :: rlib.Vector2{1600, 900}
    world := World{
        screen = DEFAULT_SCREEN,
        cam = { zoom = 5, offset = DEFAULT_SCREEN * 0.5 },
        player = {
            rect = { height = PLAYER_SIZE, width = PLAYER_SIZE },
        },
        boxes = {
            {
                mode = {.Sidescroller, .TopDown},
                rect = {x = 100, y = 100, height = 20, width = 20},
            },
        },
    }
    defer delete(world.boxes)

    rlib.SetConfigFlags({ .VSYNC_HINT })
    rlib.InitWindow(i32(world.screen.x), i32(world.screen.y), "Dunkey game")
    defer rlib.CloseWindow()

    world.tex_atlas = {
        tile_size = 16,
        texture = rlib.LoadTexture("assets/tilemap.png"),
    }
    defer rlib.UnloadTexture(world.tex_atlas.texture)

    world.player.animation_system = &sprites.AnimationSystem{
        current_anim = "",
        animations = {
            "idle" = { start_tile = 0, end_tile = 2 },
            "walk" = { start_tile = 3, end_tile = 11 },
            "jump" = { start_tile = 12, end_tile = 15 },

            "forward" = { start_tile = 16, end_tile = 18},
        },
        atlas = {
            tile_size = 16,
            texture = rlib.LoadTexture("assets/player.png"),
        },
    }
    defer delete(world.player.animation_system.animations)
    defer rlib.UnloadTexture(world.player.animation_system.atlas.texture)

    for !rlib.WindowShouldClose() {
        dt := rlib.GetFrameTime()

        when ODIN_DEBUG {
            gui_update(&world)
        }

        input := get_input()
        update(&world, input, dt)
        draw(world)

        free_all(context.temp_allocator)
    }
}

draw :: proc(w: World) {
    rlib.BeginDrawing()
    defer rlib.EndDrawing()

    rlib.ClearBackground(rlib.LIME if w.mode == .Sidescroller else rlib.ORANGE)

    rlib.BeginMode2D(w.cam)
    for i in 0..=120 {
        cols := int(w.tex_atlas.texture.width / 16)
        x := 16 * (i % cols)
        y := 16 * (i / cols)
        rlib.DrawTextureRec(w.tex_atlas.texture, sprites.sprite(w.tex_atlas, i32(i)), {f32(x), f32(y)}, rlib.WHITE)
    }
    for box in w.boxes {
        rlib.DrawRectangleRec(box.rect, box_color(box.mode))
        // rlib.DrawTextureRec(w.tex_atlas.texture, sprite(w.tex_atlas, 0), {0, 0}, rlib.WHITE)
    }

    player_sprite := sprites.animation_rect(w.player.animation_system)
    if w.player.vel.x < 0 {
        player_sprite.width *= -1
    }
    rlib.DrawTextureRec(w.player.animation_system.atlas.texture, player_sprite, player_pos(w.player), rlib.WHITE)

    // rlib.DrawTextureRec(w.tex_atlas.texture, sprites.sprite(w.tex_atlas, i32(12)), {f32(-60), f32(-70)}, rlib.WHITE)
    // rlib.DrawRectangleRounded(w.player.rect, 0.25, 4, rlib.RED)

    when ODIN_DEBUG{
        gui_draw(w)
    }
    rlib.EndMode2D()


    FONT :: 10
    draw_text(10, 10, FONT, "%d FPS; Mode: %v", rlib.GetFPS(), w.mode)
    draw_text(10, 30, FONT, "Pos: %v", player_pos(w.player))
    draw_text(10, 40, FONT, "Vel:  %v", w.player.vel)
    draw_text(10, 50, FONT, "Grounded:  %v", w.player.is_grounded)
    draw_text(10, 60, FONT, "Player anim:  %q", w.player.animation_system.current_anim)
}

draw_text :: proc(x, y, font_size: i32, format: string, args: ..any) {
    str := fmt.ctprintf(format, ..args)
    rlib.DrawText(str, x, y, font_size, rlib.DARKBLUE)
}

box_color :: proc(mode: bit_set[GameMode]) -> rlib.Color {
    if .Sidescroller in mode && .TopDown in mode do return rlib.PURPLE
    else if .Sidescroller in mode do return rlib.BLUE
    else if .TopDown      in mode do return rlib.RED

    fmt.eprintln("box_color called on Box with empty bit_set[GameMode]")
    return rlib.BLACK
}