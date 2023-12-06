#!/usr/bin/env bash
set -o verbose

rm -r build
mkdir build

# TODO: proper build flags and build for each platform
odin build src -debug -out:'build/editor.bin'
odin build src -o:speed -out:'build/game.bin'

cp -r assets build
cp README.md build

tar -czvf build.tar.gz build