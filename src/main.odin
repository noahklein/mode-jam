package main

import "core:fmt"
import rlib "vendor:raylib"

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

    dt_acc: f32, // For fixed update
}

Player :: struct {
    rect: rlib.Rectangle,
    vel: rlib.Vector2,
    is_grounded: bool,
}

player_pos :: proc(player: Player) -> rlib.Vector2 {
    return {player.rect.x, player.rect.y}
}

player_grounded :: proc(player: Player) -> bool {
    return false
}

PLAYER_SIZE :: 100

main :: proc() {
    defer free_all(context.temp_allocator)

    DEFAULT_SCREEN :: rlib.Vector2{800, 600}
    world := World{
        screen = DEFAULT_SCREEN,
        cam = { zoom = 1, offset = DEFAULT_SCREEN * 0.5 },
        player = {rect = { height = PLAYER_SIZE, width = PLAYER_SIZE }},
        boxes = {
            {
                mode = {.Sidescroller, .TopDown},
                rect = {x = 100, y = 100, height = 20, width = 20},
            },
        },
    }


    rlib.InitWindow(i32(world.screen.x), i32(world.screen.y), "Dunkey game")
    defer rlib.CloseWindow()

    rlib.SetTargetFPS(60)
    for !rlib.WindowShouldClose() {
        dt := rlib.GetFrameTime()

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
    rlib.DrawRectangleRounded(w.player.rect, 0.1, 1, rlib.RED)
    for box in w.boxes {
        rlib.DrawRectangleRec(box.rect, box_color(box.mode))
    }
    rlib.EndMode2D()


    FONT :: 10
    draw_text(10, 10, FONT, "%d FPS; Mode: %v", rlib.GetFPS(), w.mode)
    draw_text(10, 25, FONT, "Pos: %v", player_pos(w.player))
    draw_text(10, 35, FONT, "Vel:  %v", w.player.vel)
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