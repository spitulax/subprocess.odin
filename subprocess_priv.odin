#+private
package subprocess

import "base:runtime"
import "core:encoding/ansi"
import "core:fmt"
import "core:io"
import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:strings"
import "core:sync"


g_flags: Flags_Set
// TODO: maybe use pipes
g_process_tracker: ^Process_Tracker
g_process_tracker_initialised: bool
g_process_tracker_mutex: ^sync.Mutex
g_shared_mem: rawptr
SHARED_MEM_SIZE :: 1 * mem.Megabyte
g_shared_mem_size: uint
g_shared_mem_arena: virtual.Arena
g_shared_mem_allocator: Alloc


Alloc :: runtime.Allocator
Loc :: runtime.Source_Code_Location
Default_Logger_Opts :: log.Options{.Short_File_Path, .Line}


Process_Tracker :: map[Process_Handle]^Process_Status
Process_Status :: struct {
    has_run: bool,
    log:     strings.Builder,
}


general_error_str :: proc(self: General_Error) -> string {
    switch v in self {
    case Program_Not_Found:
        return fmt.aprintf("Cannot find `%v`", v.name)
    case Process_Cannot_Exit:
        return fmt.aprintf("Process %v cannot exit: %s", v.handle, strerror(v.errno))
    case Program_Not_Executed:
        return fmt.aprintf("Process %v did not execute `%s` successfully", v.handle, v.name)
    case Program_Execution_Failed:
        return fmt.aprintf("Failed to run `%s`: %s", v.name, strerror(v.errno))
    case Spawn_Failed:
        return fmt.aprintf("Failed to spawn child process: %s", strerror(v.errno))
    }
    unreachable()
}


log_header :: proc(
    sb: ^strings.Builder,
    level: log.Level,
    color: bool,
    loc: Loc,
    bg: Maybe(string) = nil,
) {
    if color {
        color: string
        switch level {
        case .Debug:
            color = ansi.FG_BRIGHT_BLACK
        case .Warning:
            color = ansi.FG_YELLOW
        case .Fatal, .Error:
            color = ansi.FG_RED
        case .Info:
            color = ansi.FG_DEFAULT
        }
        if bg != nil {
            ansi_graphic(strings.to_writer(sb), color, bg.?)
        } else {
            ansi_graphic(strings.to_writer(sb), color)
        }
    } else {
        LEVEL_HEADERS := [?]string {
            0 ..< 10 = "[DEBUG]",
            10 ..< 20 = "[INFO]",
            20 ..< 30 = "[WARN]",
            30 ..< 40 = "[ERROR]",
            40 ..< 50 = "[FATAL]",
        }
        fmt.sbprint(sb, LEVEL_HEADERS[level])
    }

    log.do_location_header(Default_Logger_Opts, sb, loc)

    if color {
        ansi_reset(strings.to_writer(sb))
    }
}

_log :: proc(level: log.Level, str: string, loc: Loc) {
    if .Use_Context_Logger in g_flags {
        log.log(level, str, location = loc)
    } else {
        _log_no_flag(level, str, loc)
    }
}

// Prevent infinite recursion if `context.logger` is from `create_logger()`
_log_no_flag :: proc(level: log.Level, str: string, loc: Loc) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    log_header(&sb, level, true, loc)
    if level <= log.Level.Debug {
        ansi_graphic(strings.to_writer(&sb), ansi.FG_BRIGHT_BLACK)
    }
    fmt.sbprint(&sb, str)
    if level <= log.Level.Debug {
        ansi_reset(strings.to_writer(&sb))
    }
    if level >= log.Level.Warning {
        fmt.eprintln(strings.to_string(sb))
    } else {
        fmt.println(strings.to_string(sb))
    }
}

_log_fmt :: proc(level: log.Level, fmt_str: string, loc: Loc, args: ..any) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    fmt.sbprintf(&sb, fmt_str, ..args)
    _log(level, strings.to_string(sb), loc)
}

_log_sep :: proc(level: log.Level, sep: string, loc: Loc, args: ..any) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    for arg, i in args {
        if i > 0 {
            fmt.sbprint(&sb, sep)
        }
        // Fancy printing by default
        fmt.sbprintf(&sb, "%#v", arg)
    }
    _log(level, strings.to_string(sb), loc)
}

ansi_reset :: proc {
    ansi_reset_writer,
    ansi_reset_str,
}

ansi_graphic :: proc {
    ansi_graphic_writer,
    ansi_graphic_str,
}

ansi_reset_writer :: proc(writer: io.Writer) {
    fmt.wprint(writer, ansi.CSI + ansi.RESET + ansi.SGR, flush = false)
}

ansi_graphic_writer :: proc(writer: io.Writer, options: ..string) {
    fmt.wprint(
        writer,
        ansi.CSI,
        concat_string_sep(options, ";", context.temp_allocator),
        ansi.SGR,
        sep = "",
        flush = false,
    )
}

ansi_reset_str :: proc() -> string {
    return ansi.CSI + ansi.RESET + ansi.SGR
}

ansi_graphic_str :: proc(options: ..string, alloc := context.allocator) -> string {
    return fmt.aprint(
        ansi.CSI,
        concat_string_sep(options, ";", context.temp_allocator),
        ansi.SGR,
        sep = "",
        allocator = alloc,
    )
}

concat_string_sep :: proc(strs: []string, sep: string, alloc := context.allocator) -> string {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    for str, i in strs {
        if i > 0 {
            fmt.sbprint(&sb, sep)
        }
        fmt.sbprint(&sb, str)
    }
    return strings.clone(strings.to_string(sb), alloc)
}


Process_Logger_Data :: struct {
    builder: ^strings.Builder,
    mutex:   Maybe(^sync.Mutex),
}

create_process_logger :: proc(
    builder: ^strings.Builder,
    alloc := context.allocator,
    mutex: Maybe(^sync.Mutex),
) -> log.Logger {
    assert(builder != nil)

    process_logger_proc :: proc(
        logger_data: rawptr,
        level: log.Level,
        text: string,
        options: log.Options,
        loc: Loc,
    ) {
        data := cast(^Process_Logger_Data)logger_data
        mutex, mutex_ok := data.mutex.?
        if mutex_ok {
            sync.mutex_lock(mutex)
        } else {
            return
        }
        defer if mutex_ok {
            sync.mutex_unlock(mutex)
        }
        log_header(data.builder, level, true, loc, ansi.BG_BRIGHT_BLACK)
        ansi_graphic(strings.to_writer(data.builder), ansi.BG_BRIGHT_BLACK)
        fmt.sbprintf(data.builder, text)
        ansi_reset(strings.to_writer(data.builder))
    }

    // NOTE: I only intend to allocate this to the shared arena for now
    data := new(Process_Logger_Data, alloc)
    data^ = Process_Logger_Data {
        builder = builder,
        mutex   = mutex,
    }
    return log.Logger{process_logger_proc, data, log.Level.Debug, Default_Logger_Opts}
}

