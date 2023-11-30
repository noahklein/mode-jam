#!/usr/bin/env bash

# TODO: proper build flags and build for each platform
odin build src -debug

mkdir build
cp src.bin build
cp -r assets build

