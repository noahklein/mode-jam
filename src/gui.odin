package main

import "core:fmt"
import rlib "vendor:raylib"

Gui :: struct {
    is_dragging: bool,
    dragging_start: rlib.Vector2,
}

gui_update :: proc(w: ^World) {
    mouse_pos := mouse_to_world(w.cam)
    if rlib.IsMouseButtonPressed(.LEFT) {
        w.gui.dragging_start = mouse_pos
        w.gui.is_dragging = true
    }

    if rlib.IsMouseButtonReleased(.LEFT) && w.gui.is_dragging {
        defer w.gui.is_dragging = false

        append(&w.boxes, Box{
            mode = {w.mode},
            rect = normalize_rect(w.gui.dragging_start, mouse_pos)
        })
    }
}

gui_draw :: proc(w: World) {
    if w.gui.is_dragging {
        rect_outline := normalize_rect(w.gui.dragging_start, mouse_to_world(w.cam))
        rlib.DrawRectangleLinesEx(rect_outline, 2, rlib.WHITE)
    }
}

mouse_to_world :: #force_inline proc(cam: rlib.Camera2D) -> rlib.Vector2 {
    return rlib.GetScreenToWorld2D(rlib.GetMousePosition(), cam)
}

normalize_rect :: #force_inline proc(a, b: rlib.Vector2) -> rlib.Rectangle {
    return {
        x = min(a.x, b.x), y = min(a.y, b.y),
        width = abs(a.x - b.x),
        height = abs(a.y - b.y),
    }
}