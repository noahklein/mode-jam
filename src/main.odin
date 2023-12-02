package main

import "core:fmt"
import "core:mem"
import rl "vendor:raylib"
import "sprites"

GameMode :: enum u8 {
    Sidescroller,
    TopDown,
}

World :: struct {
    mode: GameMode,
    screen: rl.Vector2,
    cam : rl.Camera2D,
    player: Player,
    boxes: [dynamic]Box,

    tex_atlas: sprites.Atlas,
    gui: Gui,

    dt_acc: f32, // For fixed update
}

Player :: struct {
    rect: rl.Rectangle,
    vel: rl.Vector2,
    is_grounded: bool,

    facing_dir: Direction,
    anim: ^sprites.AnimationSystem(PlayerAnimation),
}

PlayerAnimation :: enum u8 {
    Idle, Walk, Jump, // Sidescroller
    Forward,          // TopDown
}

PLAYER_ANIMATIONS := [PlayerAnimation]sprites.Animation{
    .Idle = {    start_tile = 0,  end_tile = 2,  duration = 2 },
    .Walk = {    start_tile = 3,  end_tile = 11, duration = 1 },
    .Jump = {    start_tile = 12, end_tile = 15, duration = JUMP_APEX_TIME },

    .Forward = { start_tile = 16, end_tile = 18, duration = 2},
}

Direction :: enum { North, East, South, West, }

player_pos :: proc(player: Player) -> rl.Vector2 {
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

    DEFAULT_SCREEN :: rl.Vector2{1600, 900}
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

    config_load("first.level", &world)

    rl.SetConfigFlags({ .VSYNC_HINT })
    rl.InitWindow(i32(world.screen.x), i32(world.screen.y), "Dunkey game")
    defer rl.CloseWindow()

    rl.GuiEnable()

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
    sprites.play(world.player.anim, PlayerAnimation.Idle)

    for !rl.WindowShouldClose() {
        dt := rl.GetFrameTime()

        when ODIN_DEBUG {
            gui_update(&world)
            if world.gui.is_dragging {
                dt = 0
            }
        }

        input := get_input(world)
        update(&world, input, dt)
        draw(world)

        free_all(context.temp_allocator)
    }
}

draw :: proc(w: World) {
    rl.BeginDrawing()
    defer rl.EndDrawing()

    rl.ClearBackground(rl.GRAY if w.mode == .Sidescroller else rl.ORANGE)

    rl.BeginMode2D(w.cam)

    for box in w.boxes {
        // @TODO: cull off-screen boxes

        if box.is_portal {
            if w.mode in box.mode {
                rect := sprites.sprite(w.tex_atlas, 0)
                rl.DrawTextureRec(w.tex_atlas.texture, rect, {box.rect.x, box.rect.y}, rl.WHITE)
            }
            continue
        }

        if w.mode in box.mode {
            // Draw drop shadow under object.
            OFFSET :: 1
            shadow := rl.Rectangle{ box.rect.x + OFFSET, box.rect.y + OFFSET, box.rect.width, box.rect.height}
            rl.DrawRectangleRec(shadow, {0, 0, 0, 150})
        }


        color := box_color(box.mode)
        if w.mode not_in box.mode {
            color.a = 200
        }
        rl.DrawRectangleRec(box.rect, color)
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
    if .Sidescroller in mode && .TopDown in mode do return rl.PURPLE
    else if .Sidescroller in mode do return rl.BLUE
    else if .TopDown      in mode do return rl.RED

    fmt.eprintln("box_color called on Box with empty bit_set[GameMode]")
    return rl.BLACK
}