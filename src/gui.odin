package main

import "core:fmt"
import rl "vendor:raylib"

Gui :: struct {
    is_dragging: bool,
    dragging_start: rl.Vector2,
}

gui_update :: proc(w: ^World) {
    mouse_pos := mouse_to_world(w.cam)
    if rl.IsMouseButtonPressed(.LEFT) {
        w.gui.dragging_start = mouse_pos
        w.gui.is_dragging = true
    }

    if rl.IsMouseButtonReleased(.LEFT) && w.gui.is_dragging {
        defer w.gui.is_dragging = false

        append(&w.boxes, Box{
            mode = {w.mode},
            rect = normalize_rect(w.gui.dragging_start, mouse_pos)
        })
    }
}

gui_draw :: proc(w: World) {
    if w.gui.is_dragging {
        mouse := mouse_to_world(w.cam)
        rect_outline := normalize_rect(w.gui.dragging_start, mouse)

        width := i32(rect_outline.width) - (i32(rect_outline.width) % PLAYER_SIZE)
        height := i32(rect_outline.height) - (i32(rect_outline.height) % PLAYER_SIZE)

        rect_outline.width, rect_outline.height = f32(width), f32(height)

        rl.DrawRectangleLinesEx(rect_outline, 2, rl.WHITE)
        for x := i32(0); x < width; x += PLAYER_SIZE {
            for y := i32(0); y < height; y += PLAYER_SIZE {
                pos := w.gui.dragging_start + {f32(x), f32(y)}
                grid_box := rl.Rectangle{
                    pos.x, pos.y,
                    f32(PLAYER_SIZE), f32(PLAYER_SIZE),
                }
                rl.DrawRectangleLinesEx(grid_box, 1, rl.WHITE)
            }
        }

        coord_text := fmt.ctprintf("%v, %v", width, height)
        rl.DrawText(coord_text, i32(mouse.x + 1), i32(mouse.y + 1), 7, rl.WHITE)
    }
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