package main

import "core:fmt"
import "core:time"
import rl "vendor:raylib"
import "core:math/linalg"

Gui :: struct {
    is_dragging: bool,
    drag_start: rl.Vector2,
    drag_mode: GuiDragMode,
    tile_type: BoxType,
    status: GuiStatus,

    hide_grid: bool,
}


GuiDragMode :: enum u8 { Normal, Reverse, Both }

gui_update :: proc(w: ^World, dt: f32) {
    both := rl.IsKeyDown(.LEFT_CONTROL)
    reverse := !both && rl.IsKeyDown(.LEFT_SHIFT)

    if rl.IsKeyDown(.LEFT_CONTROL)    do w.gui.drag_mode = .Both
    else if rl.IsKeyDown(.LEFT_SHIFT) do w.gui.drag_mode = .Reverse
    else                              do w.gui.drag_mode = .Normal

    if      rl.IsKeyPressed(.ONE)   do w.gui.tile_type = .Wall
    else if rl.IsKeyPressed(.TWO)   do w.gui.tile_type = .Portal
    else if rl.IsKeyPressed(.THREE) do w.gui.tile_type = .Push
    else if rl.IsKeyPressed(.FOUR)  do w.gui.tile_type = .Checkpoint
    else if rl.IsKeyPressed(.FIVE)  do w.gui.tile_type = .Spike

    if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.S) {
        err := config_save(LEVEL_FILE, w^)
        if err != nil {
            fmt.eprintln("Failed to save level:", err)
            gui_status(&w.gui.status, "Error! Failed to save level " + LEVEL_FILE)
        } else {
            gui_status(&w.gui.status, "Saved level to " + LEVEL_FILE)
        }
    } else if rl.IsKeyDown(.LEFT_CONTROL)  && rl.IsKeyPressed(.O) {
        // clear(&w.boxes)
        if err := config_load(LEVEL_FILE, w); err != nil {
            fmt.eprintln("Failed to load level:", err)
            gui_status(&w.gui.status, "Error! Failed to load level " + LEVEL_FILE)
        } else {
            gui_status(&w.gui.status, "Loaded level from " + LEVEL_FILE)
        }
    }

    if rl.IsKeyPressed(.G) {
        w.gui.hide_grid = !w.gui.hide_grid
    }

    if scroll := rl.GetMouseWheelMove(); scroll != 0 {
        w.cam.zoom += rl.GetMouseWheelMove() * 0.25
        w.cam.zoom = clamp(w.cam.zoom, 0.2, 10)
    }

    // Update status bar timer.
    if w.gui.status.msg != "" {
        w.gui.status.elapsed -= dt
        if w.gui.status.elapsed <= 0 {
            w.gui.status.elapsed = 0
            w.gui.status.msg = ""
        }
    }


    if w.gui.tile_type != .Wall && w.gui.tile_type != .Checkpoint {
        w.gui.is_dragging = false // Dragging only allowed for some types.
    }

    modes : bit_set[GameMode]
    switch w.gui.drag_mode {
        case .Both:    modes = {.Sidescroller, .TopDown}
        case .Reverse: modes = {inverse_mode(w.mode)}
        case .Normal:  modes = {w.mode}
    }

    mouse := mouse_to_world(w.cam)
    if rl.IsMouseButtonPressed(.RIGHT) {
        if w.gui.is_dragging {
            w.gui.is_dragging = false // Cancel drag.
        } else {
            // Delete hovered box
            for box, i in w.boxes {
                if rl.CheckCollisionPointRec(mouse, box.rect) {
                    unordered_remove(&w.boxes, i)
                    break
                }
            }
        }
    }

    // Ctrl+Z is not exactly undo...
    if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.Z) {
        if len(w.boxes) > 0 do pop(&w.boxes)
    }


    if rl.IsMouseButtonPressed(.LEFT) {
        hovered := snap_down_mouse(mouse)
        switch w.gui.tile_type {
        case .Wall, .Checkpoint:
            w.gui.drag_start = hovered
            w.gui.is_dragging = true
        case .Portal:
            append(&w.boxes, new_portal(modes, hovered))
        case .Push:
            append(&w.boxes, new_push(hovered))
        case .Spike:
            append(&w.boxes, new_spike(hovered))
        }
    }

    if w.gui.is_dragging && rl.IsMouseButtonReleased(.LEFT) {
        defer w.gui.is_dragging = false

        hovered := snap_up_mouse(mouse)
        rect := normalize_rect(w.gui.drag_start, {f32(hovered.x), f32(hovered.y)})
        if rect.width == 0 || rect.height == 0 {
            return
        }

        #partial switch w.gui.tile_type {
        case .Wall: append(&w.boxes, new_wall(modes, rect))
        case .Checkpoint: append(&w.boxes, new_checkpoint(rect))
        case: fmt.panicf("dragging only allowed on walls and checkpoints: got %v", w.gui.tile_type)
        }
    }
}

mouse_grid_tile : rl.Vector2
gui_draw2d :: proc(w: World) {
    GRID_SIZE :: PLAYER_SIZE * 300
    if !w.gui.hide_grid {
        rect := rl.Rectangle{-GRID_SIZE, -GRID_SIZE, 2 * GRID_SIZE, 2 * GRID_SIZE}
        rl.GuiGrid(rect, "grid", PLAYER_SIZE, 1, &mouse_grid_tile)
    }

    mouse := mouse_to_world(w.cam)
    hovered := snap_down_mouse(mouse)

    {
    // Draw cursor snapped to grid.
    PAD :: 5
    rl.DrawRectangleV(hovered + PAD, PLAYER_SIZE_V - 2 * PAD, drag_color(w.mode, w.gui.drag_mode))
    }

    if w.gui.tile_type != .Portal && w.gui.is_dragging {
        rect_outline := normalize_rect(w.gui.drag_start, snap_up_mouse(mouse))
        rl.DrawRectangleLinesEx(rect_outline, 2, drag_color(w.mode, w.gui.drag_mode))

        coord_text := fmt.ctprintf("%v, %v", rect_outline.width, rect_outline.height)
        rl.DrawText(coord_text, i32(mouse.x + 1), i32(mouse.y + 1), 1, rl.WHITE)
        more_info := fmt.ctprintf("%v, %v", w.gui.drag_mode, w.gui.tile_type)
        rl.DrawText(more_info, i32(mouse.x + 1), i32(mouse.y + 8), 1, rl.WHITE)
    }
}

gui_draw :: proc(w: World) {
    FONT :: 10
    {
    // Top-left panel
    X :: 10
    Y :: 10
    TITLE :: 18
    rl.GuiPanel({0, 0, 200, 10 * Y}, fmt.ctprintf("Mode: %v", w.mode))
    draw_text(X, 1 * Y + TITLE, FONT, "%d FPS", rl.GetFPS())
    draw_text(X, 2 * Y + TITLE, FONT, "Pos: %v", player_pos(w.player))
    draw_text(X, 3 * Y + TITLE, FONT, "Vel:  %v", w.player.vel)
    draw_text(X, 4 * Y + TITLE, FONT, "Grounded:  %v", w.player.is_grounded)
    draw_text(X, 5 * Y + TITLE, FONT, "Player anim:  %q", w.player.anim.current_anim)
    draw_text(X, 6 * Y + TITLE, FONT, "Tile type: %v", w.gui.tile_type)
    }
    // draw_text(X, 6 * Y + TITLE, FONT, physics_stat_report(w.physics_stats))

    {
    // Top-right panel
    X := i32(w.screen.x - 200)
    Y :: 10
    TITLE :: 18
    rl.GuiPanel({f32(X - 10), 0, w.screen.x, 10 * Y}, "Stats")
    draw_text(X, 1 * Y + TITLE, FONT, "Physics: %3.2f%%, %.2v", stats_physics_pct(w.timers), time.stopwatch_duration(w.timers.physics))
    draw_text(X, 2 * Y + TITLE, FONT, "Draw:  %4.2f%%, %.2v", stats_draw_pct(w.timers), time.stopwatch_duration(w.timers.draw))
    }

    if w.gui.status.msg != "" {
        STATUS_HEIGHT :: 25
        rl.GuiStatusBar({0, w.screen.y - STATUS_HEIGHT, w.screen.x, STATUS_HEIGHT}, w.gui.status.msg)
    }
}

drag_color :: proc(mode: GameMode, drag_mode: GuiDragMode) -> rl.Color {
    switch drag_mode {
        case .Both:    return box_color({.Sidescroller, .TopDown})
        case .Reverse: return box_color({inverse_mode(mode)})
        case .Normal:  return box_color({mode})
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

GuiStatus :: struct {
    msg: cstring,
    elapsed: f32,
}

gui_status :: proc(status: ^GuiStatus, msg: cstring) {
    status.msg = msg
    status.elapsed = 3
}