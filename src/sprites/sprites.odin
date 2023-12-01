package sprites

import rl "vendor:raylib"
import "core:fmt"

Atlas :: struct {
    tile_size: i32,
    texture: rl.Texture,
}

sprite :: proc(using atlas: Atlas, tile_id: i32) -> (rl.Rectangle) {
    rows := texture.width / tile_size
    x, y := tile_id % rows, tile_id / rows
    return {
        x = f32(x * tile_size),
        y = f32(y * tile_size),
        width = f32(tile_size),
        height = f32(tile_size),
    }
}

Animation :: struct {
    start_tile, end_tile: i32,
    duration: f32,
}

AnimationSystem :: struct($Key: typeid) {
    atlas: Atlas,
    animations: [Key]Animation,

    // Animation state.
    current_anim: Key,
    elapsed, time_per_frame: f32,
    current_tile: i32,
}

play :: proc(sys: ^AnimationSystem($Key), key: Key) {
    if key == sys.current_anim {
        return
    }

    anim := sys.animations[key]
    sys.elapsed = 0
    sys.current_anim = key
    sys.current_tile = anim.start_tile
    sys.time_per_frame = anim.duration / f32(anim.end_tile - anim.start_tile)
}

update :: proc(sys: ^AnimationSystem($Key), dt: f32) {
    anim := sys.animations[sys.current_anim]
    assert(anim.start_tile < anim.end_tile, "animation: start_tile must be less than end_tile")

    sys.elapsed += dt
    if sys.elapsed >= sys.time_per_frame {
        sys.elapsed -= sys.time_per_frame
        sys.current_tile += 1

        if sys.current_tile > anim.end_tile {
            sys.current_tile = anim.start_tile
        }
    }
}

animation_rect :: proc(sys: ^AnimationSystem($Key)) -> rl.Rectangle {
    return sprite(sys.atlas, sys.current_tile)
}