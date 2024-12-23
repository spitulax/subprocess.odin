#+private
package subprocess

import "base:runtime"
import "core:encoding/ansi"
import "core:fmt"
import "core:io"
import "core:log"
import "core:strings"
import "core:sync"


g_flags: Global(Flags_Set)


OS_Set :: bit_set[runtime.Odin_OS_Type]
Alloc :: runtime.Allocator
Loc :: runtime.Source_Code_Location
Default_Logger_Opts :: log.Options{.Short_File_Path, .Line}
Global :: struct($T: typeid) {
    value: T,
    mutex: sync.RW_Mutex,
}


when ODIN_OS in POSIX_OS {
    NL :: "\n"
    SH :: "/bin/sh"
    CMD :: "-c" // shell flag to execute the next argument as a command
} else when ODIN_OS in WINDOWS_OS {
    NL :: "\r\n"
    SH :: "cmd.exe"
    CMD :: "/C"
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
    if .Use_Context_Logger in default_flags() {
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
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
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
    sb := strings.builder_make(alloc)
    fmt.sbprint(&sb, ansi.CSI)
    append_concat_string_sep(strings.to_writer(&sb), options, ";")
    fmt.sbprint(&sb, ansi.SGR)
    return strings.to_string(sb)
}

concat_string_sep :: proc(strs: []string, sep: string, alloc := context.allocator) -> string {
    sb := strings.builder_make(alloc)
    for str, i in strs {
        if i > 0 {
            fmt.sbprint(&sb, sep)
        }
        fmt.sbprint(&sb, str)
    }
    return strings.to_string(sb)
}

append_concat_string_sep :: proc(w: io.Writer, strs: []string, sep: string) {
    for str, i in strs {
        if i > 0 {
            fmt.wprint(w, sep)
        }
        fmt.wprint(w, str)
    }
}

trim_nl :: proc(s: string) -> string {
    return strings.trim_suffix(s, NL)
}


// NOTE: What this procedure prints should be runnable inside the system shell without modification
echo_command :: proc(
    opts: Exec_Opts,
    mode: Escaping_Mode,
    prog: string,
    args: []string,
    loc: Loc,
) {
    if opts.dont_echo_command {return}
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    if default_flags() & {.Echo_Commands, .Echo_Commands_Debug} != {} {
        msg := fmt.tprintf(
            "(%v|%v) %s",
            opts.output,
            opts.input,
            combine_args(prog, args, mode, context.temp_allocator),
        )
        if .Echo_Commands in default_flags() {
            log_info(msg, loc = loc)
        } else if .Echo_Commands_Debug in default_flags() {
            log_debug(msg, loc = loc)
        }
    }
}

Escaping_Mode :: enum {
    // Escaping for POSIX shell
    POSIX,
    // Escaping for `CreateProcessW`
    Win_API,
    // (No) Escaping for `cmd.exe /C ...`
    Win_Cmd,
}

combine_args :: proc(
    prog: string,
    args: []string,
    mode: Escaping_Mode,
    alloc := context.allocator,
    loc := #caller_location,
) -> string {
    b := strings.builder_make(alloc)
    for i in -1 ..< len(args) {
        s: string
        if i == -1 {
            s = prog
        } else {
            s = args[i]
            strings.write_rune(&b, ' ')
        }

        when ODIN_OS in POSIX_OS {
            QUOTED :: "|&;<>()$`\\\"'*?[#~=%"
        } else when ODIN_OS in WINDOWS_OS {
            QUOTED :: "&<>[]|{}^=;!'+,`~%"
        }
        // NOTE: `strings.write_quoted_string` will always quote the string
        need_quoting :=
            mode != .Win_Cmd && (strings.contains_space(s) || strings.contains_any(s, QUOTED))

        if need_quoting {
            strings.write_rune(&b, '"')
        }

        for c, j in s {
            escape := false

            switch mode {
            case .POSIX:
                switch c {
                case '"', '$', '\\', '`':
                    escape = true
                }
            case .Win_API:
                switch c {
                case '\\':
                    escape = s[j + 1] == '"'
                case '"':
                    escape = true
                }
            case .Win_Cmd:
            }

            if escape {
                strings.write_rune(&b, '\\')
            }
            strings.write_rune(&b, c)
        }

        if need_quoting {
            strings.write_rune(&b, '"')
        }
    }

    return strings.to_string(b)
}

process_wait_assert :: proc(self: ^Process) {
    stdout_pipe_ok := self.stdout_pipe != nil
    stderr_pipe_ok := self.stderr_pipe != nil
    stdin_pipe_ok := self.stdin_pipe != nil
    MSG :: "The state of `Process` does not match its `opts`"
    switch self.opts.output {
    case .Share, .Silent:
        assert(!stdout_pipe_ok && !stderr_pipe_ok, MSG)
    case .Capture:
        assert(stdout_pipe_ok && stderr_pipe_ok, MSG)
    case .Capture_Combine:
        assert(stdout_pipe_ok && !stderr_pipe_ok, MSG)
    }
    switch self.opts.input {
    case .Share, .Nothing:
        assert(!stdin_pipe_ok, MSG)
    case .Pipe:
        assert(stdin_pipe_ok, MSG)
    }
}

