package main

import "core:fmt"
import "core:os"
import "core:io"
import "core:runtime"
import "core:strings"
import "core:strconv"

MarshalDataError :: enum { None, FileOpen, NoWriter, TruncateFile }
MarshalError     :: union { io.Error, MarshalDataError }


UnmarshalDataError :: enum { None, FileRead, ParseFloat, ParseUint }
UnmarshalError :: union {io.Error, UnmarshalDataError}

config_save :: proc(path: string, w: World) -> MarshalError {
    when !ODIN_DEBUG { return nil }
    context.allocator = context.temp_allocator

    file, errno := os.open(path, os.O_CREATE | os.O_WRONLY, 0o755)
    if errno != os.ERROR_NONE {
        return .FileOpen
    }
    defer os.close(file)
    if ok := os.write_entire_file(path, nil); !ok {
        return .TruncateFile
    }

    writer, ok := io.to_writer(os.stream_from_handle(file))
    if !ok {
        return .NoWriter
    }

    return marshal(writer, w)
}

marshal :: proc(writer: io.Writer, world: World) -> MarshalError {
    for box in world.boxes {
        using box

        acc : u8
        for m, i in GameMode do if m in mode {
            acc |= 1 << u32(i)
        }

        switch type {
        case .Portal:
            fmt.wprintln(writer, "P", rect.x, rect.y, rect.width, rect.height, acc)
        case .Wall:
            fmt.wprintln(writer, "B", rect.x, rect.y, rect.width, rect.height, acc)
        case .Push:
            fmt.wprintln(writer, "X", rect.x, rect.y, rect.width, rect.height, acc)
        }
    }

    return nil
}

config_load :: proc(path: string, w: ^World) -> UnmarshalError {
    bytes, ok := os.read_entire_file(path, context.temp_allocator)
    if !ok { return .FileRead }

    data := string(bytes)
    lines := strings.split(data, "\n", context.temp_allocator)

    for line in lines {
        tokens := strings.split(line, " ", context.temp_allocator)
        assert(len(tokens) > 0, "Empty line")
        switch tokens[0] {
        case "B":
            box := parse_box(tokens[1:]) or_return
            append(&w.boxes, box)
        case "P":
            box := parse_box(tokens[1:]) or_return
            box.type = .Portal
            append(&w.boxes, box)
        case "X":
            box := parse_box(tokens[1:]) or_return
            box.type = .Push
            append(&w.boxes, box)
        case "":
        case:
            fmt.panicf("Unrecognized box type in level %q: %q", path, tokens[0])
        }
    }

    return nil
}

parse_box :: proc(tokens: []string) -> (box: Box, err: UnmarshalError) {
    assert(len(tokens) == 5, "Not enough args for Box")

    box.rect.x = atof(tokens[0]) or_return
    box.rect.y = atof(tokens[1]) or_return
    box.rect.width  = atof(tokens[2]) or_return
    box.rect.height = atof(tokens[3]) or_return

    mode_uint := atou(tokens[4]) or_return
    for mode, i in GameMode {
        i := uint(i)
        if mode_uint & (1 << i) != 0 {
            box.mode += {mode}
        }
    }

    return box, nil
}

@(require_results)
atof :: #force_inline proc(s: string) -> (f32, UnmarshalError) {
    f, ok := strconv.parse_f32(s)
    if !ok {
        return 0, .ParseFloat
    }
    return f, nil
}

@(require_results)
atou :: #force_inline proc(s: string) -> (uint, UnmarshalError) {
    u, ok := strconv.parse_uint(s)
    if !ok {
        return 0, .ParseUint
    }
    return u, nil
}