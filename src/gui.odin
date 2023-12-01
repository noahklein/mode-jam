package main

import "core:fmt"
import rl "vendor:raylib"
import "core:math/linalg"

Gui :: struct {
    is_dragging: bool,
    drag_start: rl.Vector2,
    drag_mode: GuiDragMode,
    tile_type: GuiTileType,
}

GuiDragMode :: enum u8 { Normal, Reverse, Both }
GuiTileType :: enum u8 { Box, Portal }

gui_update :: proc(w: ^World) {
    mouse := mouse_to_world(w.cam)
    if rl.IsMouseButtonPressed(.LEFT) {
        w.gui.drag_start = mouse
        w.gui.is_dragging = true
    }

    both := rl.IsKeyDown(.LEFT_CONTROL)
    reverse := !both && rl.IsKeyDown(.LEFT_SHIFT)

    if rl.IsKeyDown(.LEFT_CONTROL)    do w.gui.drag_mode = .Both
    else if rl.IsKeyDown(.LEFT_SHIFT) do w.gui.drag_mode = .Reverse
    else                              do w.gui.drag_mode = .Normal

    if rl.IsKeyPressed(.ONE) do w.gui.tile_type = .Box
    else if rl.IsKeyPressed(.TWO) do w.gui.tile_type = .Portal

    if rl.IsMouseButtonReleased(.LEFT) && w.gui.is_dragging {
        defer w.gui.is_dragging = false

        snapped := [2]i32{
            round_to_multiple(i32(mouse.x - w.gui.drag_start.x), PLAYER_SIZE),
            round_to_multiple(i32(mouse.y - w.gui.drag_start.y), PLAYER_SIZE),
        }
        end := w.gui.drag_start + {f32(snapped.x), f32(snapped.y)}
        rect := normalize_rect(w.gui.drag_start, end)
        if rect.width == 0 || rect.height == 0 {
            return
        }

        modes : bit_set[GameMode]
        switch w.gui.drag_mode {
            case .Both:    modes = {.Sidescroller, .TopDown}
            case .Reverse: modes = {inverse_mode(w.mode)}
            case .Normal:  modes = {w.mode}
        }

        append(&w.boxes, Box{
            mode = modes,
            rect = rect,
            is_portal = w.gui.tile_type == .Portal,
        })
    }
}

gui_draw :: proc(w: World) {
    mouse := mouse_to_world(w.cam)

    if w.gui.tile_type == .Portal {
        mouse_tile := snap_to_grid(mouse, PLAYER_SIZE)
        rl.DrawRectangleLinesEx({mouse_tile.x, mouse_tile.y, PLAYER_SIZE, PLAYER_SIZE}, 2, drag_color(w.gui.drag_mode))
        return
    }

    if w.gui.is_dragging {
        snapped := snap_to_grid(mouse - w.gui.drag_start, PLAYER_SIZE)

        end := w.gui.drag_start + snapped
        rect_outline := normalize_rect(w.gui.drag_start, end)

        rl.DrawRectangleLinesEx(rect_outline, 2, drag_color(w.gui.drag_mode))

        coord_text := fmt.ctprintf("%v, %v", rect_outline.width, rect_outline.height)
        rl.DrawText(coord_text, i32(mouse.x + 1), i32(mouse.y + 1), 1, rl.WHITE)
        more_info := fmt.ctprintf("%v, %v", w.gui.drag_mode, w.gui.tile_type)
        rl.DrawText(more_info, i32(mouse.x + 1), i32(mouse.y + 8), 1, rl.WHITE)
    }
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
round_to_multiple :: #force_inline proc(n: i32, $mult: i32) -> i32 {
    #assert(mult != 0)
    return ((n + mult / 2) / mult) * mult
}

@(require_results)
snap_to_grid :: #force_inline proc(v: rl.Vector2, $tile_size: i32) -> rl.Vector2 {
    return {
        f32(round_to_multiple(i32(v.x), tile_size)),
        f32(round_to_multiple(i32(v.y), tile_size)),
    }
}

inverse_mode :: #force_inline proc(mode: GameMode) -> GameMode {
    return .Sidescroller if mode == .TopDown else .TopDown
}