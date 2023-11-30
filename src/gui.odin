package main

import "core:fmt"
import rl "vendor:raylib"
import "core:math/linalg"

Gui :: struct {
    is_dragging: bool,
    drag_start: rl.Vector2,
    drag_mode: GuiDragMode,
}

GuiDragMode :: enum u8 { Normal, Reverse, Both }

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
        })
    }
}

gui_draw :: proc(w: World) {
    if w.gui.is_dragging {
        mouse := mouse_to_world(w.cam)
        snapped := [2]i32{
            round_to_multiple(i32(mouse.x - w.gui.drag_start.x), PLAYER_SIZE),
            round_to_multiple(i32(mouse.y - w.gui.drag_start.y), PLAYER_SIZE),
        }
        end := w.gui.drag_start + {f32(snapped.x), f32(snapped.y)}
        rect_outline := normalize_rect(w.gui.drag_start, end)

        rl.DrawRectangleLinesEx(rect_outline, 2, drag_color(w.gui.drag_mode))

        coord_text := fmt.ctprintf("%v, %v - %v", rect_outline.width, rect_outline.height, w.gui.drag_mode)
        rl.DrawText(coord_text, i32(mouse.x + 1), i32(mouse.y + 1), 3, rl.WHITE)
    }
}

drag_color :: proc(mode: GuiDragMode) -> rl.Color {
    switch mode {
        case .Both: return rl.PURPLE
        case .Reverse: return rl.BLACK
        case .Normal: return rl.WHITE
    }

    panic("Unsupported drag mode, can't get color")
}

mouse_to_world :: #force_inline proc(cam: rl.Camera2D) -> rl.Vector2 {
    return rl.GetScreenToWorld2D(rl.GetMousePosition(), cam)
}

normalize_rect :: #force_inline proc(a, b: rl.Vector2) -> rl.Rectangle {
    return {
        x = min(a.x, b.x), y = min(a.y, b.y),
        width = abs(a.x - b.x),
        height = abs(a.y - b.y),
    }
}

round_to_multiple :: #force_inline proc(n: i32, $mult: i32) -> i32 {
    #assert(mult != 0)
    return ((n + mult / 2) / mult) * mult
}

inverse_mode :: #force_inline proc(mode: GameMode) -> GameMode {
    return .Sidescroller if mode == .TopDown else .TopDown
}