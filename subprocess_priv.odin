package subprocess

import "base:runtime"
import "core:encoding/ansi"
import "core:fmt"
import "core:io"
import "core:log"
import "core:strings"


g_use_context_logger: bool


Loc :: runtime.Source_Code_Location
Default_Logger_Opts :: log.Options{.Short_File_Path, .Line}

_log :: proc(
    level: log.Level,
    sb: strings.Builder,
    loc := #caller_location,
    use_context_logger: bool = g_use_context_logger,
) {
    if use_context_logger {
        log.log(level, strings.to_string(sb), location = loc)
    } else {
        sb_loc := strings.builder_make()
        defer strings.builder_destroy(&sb_loc)
        color: string
        switch level {
        case .Debug:
            color = ansi.FG_BLUE
        case .Warning:
            color = ansi.FG_YELLOW
        case .Fatal:
        case .Error:
            color = ansi.FG_RED
        case .Info:
            color = ansi.RESET
        }
        ansi_graphic(strings.to_writer(&sb_loc), color)
        log.do_location_header(Default_Logger_Opts, &sb_loc, loc)
        ansi_reset(strings.to_writer(&sb_loc))
        fmt.sbprintf(&sb_loc, strings.to_string(sb))
        if level >= log.Level.Warning {
            fmt.eprintln(strings.to_string(sb_loc))
        } else {
            fmt.println(strings.to_string(sb_loc))
        }
    }
}

_log_fmt :: proc(
    level: log.Level,
    fmt_str: string,
    loc: Loc,
    use_context_logger: bool,
    args: ..any,
) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    fmt.sbprintf(&sb, fmt_str, ..args)
    _log(level, sb, loc, use_context_logger)
}

_log_sep :: proc(level: log.Level, sep: string, loc: Loc, use_context_logger: bool, args: ..any) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    for arg, i in args {
        if i > 0 {
            fmt.sbprint(&sb, sep)
        }
        fmt.sbprint(&sb, arg)
    }
    _log(level, sb, loc, use_context_logger)
}

log_error :: proc(
    args: ..any,
    sep: string = " ",
    loc := #caller_location,
    use_context_logger: bool = g_use_context_logger,
) {
    _log_sep(.Error, sep, loc, use_context_logger, ..args)
}

log_errorf :: proc(
    fmt: string,
    args: ..any,
    loc := #caller_location,
    use_context_logger: bool = g_use_context_logger,
) {
    _log_fmt(.Error, fmt, loc, use_context_logger, ..args)
}

log_warn :: proc(
    args: ..any,
    sep: string = " ",
    loc := #caller_location,
    use_context_logger: bool = g_use_context_logger,
) {
    _log_sep(.Warning, sep, loc, use_context_logger, ..args)
}

log_warnf :: proc(
    fmt: string,
    args: ..any,
    loc := #caller_location,
    use_context_logger: bool = g_use_context_logger,
) {
    _log_fmt(.Warning, fmt, loc, use_context_logger, ..args)
}

log_info :: proc(
    args: ..any,
    sep: string = " ",
    loc := #caller_location,
    use_context_logger: bool = g_use_context_logger,
) {
    _log_sep(.Info, sep, loc, use_context_logger, ..args)
}

log_infof :: proc(
    fmt: string,
    args: ..any,
    loc := #caller_location,
    use_context_logger: bool = g_use_context_logger,
) {
    _log_fmt(.Info, fmt, loc, use_context_logger, ..args)
}

log_debug :: proc(
    args: ..any,
    sep: string = " ",
    loc := #caller_location,
    use_context_logger: bool = g_use_context_logger,
) {
    _log_sep(.Debug, sep, loc, use_context_logger, ..args)
}

log_debugf :: proc(
    fmt: string,
    args: ..any,
    loc := #caller_location,
    use_context_logger: bool = g_use_context_logger,
) {
    _log_fmt(.Debug, fmt, loc, use_context_logger, ..args)
}

ansi_reset :: proc(w: io.Writer) {
    fmt.wprint(w, ansi.CSI + ansi.RESET + ansi.SGR, flush = false)
}

ansi_graphic :: proc(w: io.Writer, options: ..string) {
    fmt.wprint(
        w,
        ansi.CSI,
        concat_string_sep(options, ";", context.temp_allocator),
        ansi.SGR,
        sep = "",
        flush = false,
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

