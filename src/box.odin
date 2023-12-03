package main

import rl "vendor:raylib"

Box :: struct {
    mode: bit_set[GameMode],
    rect: rl.Rectangle,
    type: BoxType,
}

BoxType :: enum u8 {
    Wall, Portal, Push
}

new_wall :: proc(modes: bit_set[GameMode], rect: rl.Rectangle) -> Box {
    return Box{
        type = .Wall,
        mode = modes,
        rect = rect,
    }
}

new_portal :: proc(modes: bit_set[GameMode], pos: rl.Vector2) -> Box {
    return Box{
        type = .Portal,
        mode = modes,
        rect = {pos.x, pos.y, PLAYER_SIZE, PLAYER_SIZE},
    }
}

new_push :: proc(pos: rl.Vector2) -> Box {
    return Box{
        type = .Push,
        mode = {.Sidescroller, .TopDown},
        rect = {pos.x, pos.y, PLAYER_SIZE, PLAYER_SIZE},
    }
}