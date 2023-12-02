package main

import "core:fmt"
import rl "vendor:raylib"
import "core:math/linalg"

Gui :: struct {
    is_dragging: bool,
    drag_start: rl.Vector2,
    drag_mode: GuiDragMode,
    tile_type: GuiTileType,

    selected_box: int,
}

GuiDragMode :: enum u8 { Normal, Reverse, Both }
GuiTileType :: enum u8 { Box, Portal }

gui_update :: proc(w: ^World) {
    both := rl.IsKeyDown(.LEFT_CONTROL)
    reverse := !both && rl.IsKeyDown(.LEFT_SHIFT)

    if rl.IsKeyDown(.LEFT_CONTROL)    do w.gui.drag_mode = .Both
    else if rl.IsKeyDown(.LEFT_SHIFT) do w.gui.drag_mode = .Reverse
    else                              do w.gui.drag_mode = .Normal

    if rl.IsKeyPressed(.ONE) do w.gui.tile_type = .Box
    else if rl.IsKeyPressed(.TWO) do w.gui.tile_type = .Portal

    if rl.IsKeyPressed(.S) && rl.IsKeyDown(.LEFT_CONTROL) {
        config_save("first.level", w^)
    }

    if w.gui.tile_type != .Box {
        w.gui.is_dragging = false // Can only drag in box mode.
    }

    modes : bit_set[GameMode]
    switch w.gui.drag_mode {
        case .Both:    modes = {.Sidescroller, .TopDown}
        case .Reverse: modes = {inverse_mode(w.mode)}
        case .Normal:  modes = {w.mode}
    }

    mouse := mouse_to_world(w.cam)
    if rl.IsMouseButtonPressed(.LEFT) {
        switch w.gui.tile_type {
            case .Portal:
                hovered := snap_down_mouse(mouse)
                append(&w.boxes, Box{
                    mode = modes,
                    rect = {hovered.x, hovered.y, PLAYER_SIZE, PLAYER_SIZE},
                    is_portal = true,
                })
            case .Box:
                w.gui.drag_start = snap_down_mouse(mouse)
                w.gui.is_dragging = true
        }
    }

    if rl.IsMouseButtonReleased(.LEFT) && w.gui.is_dragging {
        defer w.gui.is_dragging = false

        hovered := snap_up_mouse(mouse)
        rect := normalize_rect(w.gui.drag_start, {f32(hovered.x), f32(hovered.y)})
        if rect.width == 0 || rect.height == 0 {
            return
        }

        append(&w.boxes, Box{ mode = modes, rect = rect })
    }
}

mouse_grid_tile : rl.Vector2
gui_draw2d :: proc(w: World) {
    GRID_SIZE :: PLAYER_SIZE * 300
    rl.GuiGrid({-GRID_SIZE, -GRID_SIZE, 2 * GRID_SIZE, 2 * GRID_SIZE}, "grid", PLAYER_SIZE, 1, &mouse_grid_tile)

    mouse := mouse_to_world(w.cam)
    hovered := snap_down_mouse(mouse)
    rl.DrawRectangle(i32(hovered.x), i32(hovered.y), PLAYER_SIZE, PLAYER_SIZE, drag_color(w.gui.drag_mode))

    if w.gui.tile_type != .Portal && w.gui.is_dragging {
        rect_outline := normalize_rect(w.gui.drag_start, snap_up_mouse(mouse))
        rl.DrawRectangleLinesEx(rect_outline, 2, drag_color(w.gui.drag_mode))

        coord_text := fmt.ctprintf("%v, %v", rect_outline.width, rect_outline.height)
        rl.DrawText(coord_text, i32(mouse.x + 1), i32(mouse.y + 1), 1, rl.WHITE)
        more_info := fmt.ctprintf("%v, %v", w.gui.drag_mode, w.gui.tile_type)
        rl.DrawText(more_info, i32(mouse.x + 1), i32(mouse.y + 8), 1, rl.WHITE)
    }
}

gui_draw :: proc(w: World) {
    FONT :: 10
    X :: 10
    Y :: 10
    TITLE :: 18
    rl.GuiPanel({0, 0, 200, 10 * Y}, fmt.ctprintf("Mode: %v", w.mode))
    draw_text(X, 1 * Y + TITLE, FONT, "%d FPS", rl.GetFPS())
    draw_text(X, 2 * Y + TITLE, FONT, "Pos: %v", player_pos(w.player))
    draw_text(X, 3 * Y + TITLE, FONT, "Vel:  %v", w.player.vel)
    draw_text(X, 4 * Y + TITLE, FONT, "Grounded:  %v", w.player.is_grounded)
    draw_text(X, 5 * Y + TITLE, FONT, "Player anim:  %q", w.player.anim.current_anim)
}

drag_color :: proc(mode: GuiDragMode) -> rl.Color {
    switch mode {
        case .Both:    return rl.PURPLE
        case .Reverse: return rl.BLACK
        case .Normal:  return rl.WHITE
    }

    panic("Unsupported drag mode, can't get color")
}

@(require_results)
mouse_to_world :: #force_inline proc(cam: rl.Camera2D) -> rl.Vector2 {
    return rl.GetScreenToWorld2D(rl.GetMousePosition(), cam)
}

@(require_results)
normalize_rect :: #force_inline proc(a, b: rl.Vector2) -> rl.Rectangle {
    return {
        x = min(a.x, b.x), y = min(a.y, b.y),
        width = abs(a.x - b.x),
        height = abs(a.y - b.y),
    }
}

@(require_results)
round_to_multiple :: #force_inline proc(n: i32, $mult: i32) -> i32
    where mult > 0 {
    return ((n + mult / 2) / mult) * mult
}

@(require_results)
inverse_mode :: #force_inline proc(mode: GameMode) -> GameMode {
    return .Sidescroller if mode == .TopDown else .TopDown
}

@(require_results)
snap_down :: #force_inline proc(i: i32) -> i32 {
    if i < 0 {
        return ((i - PLAYER_SIZE + 1) / PLAYER_SIZE) * PLAYER_SIZE
    }

    return (i / PLAYER_SIZE) * PLAYER_SIZE
}

@(require_results)
snap_up :: #force_inline proc(i: i32) -> i32 {
    if i < 0 {
        return (i / PLAYER_SIZE) * PLAYER_SIZE
    }

    return ((i + PLAYER_SIZE - 1) / PLAYER_SIZE) * PLAYER_SIZE
}

@(require_results)
snap_down_mouse :: #force_inline proc(m: rl.Vector2) -> rl.Vector2 {
    return { f32(snap_down(i32(m.x))), f32(snap_down(i32(m.y))) }
}

@(require_results)
snap_up_mouse :: #force_inline proc(m: rl.Vector2) -> rl.Vector2 {
    return { f32(snap_up(i32(m.x))), f32(snap_up(i32(m.y))) }
}