package main

import rlib "vendor:raylib"

Box :: struct {
    mode: bit_set[GameMode],
    rect: rlib.Rectangle,
}