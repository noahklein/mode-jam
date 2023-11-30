package main

import rl "vendor:raylib"

Box :: struct {
    mode: bit_set[GameMode],
    rect: rl.Rectangle,
    is_portal: bool,
}