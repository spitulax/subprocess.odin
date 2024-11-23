package subprocess

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:time"


OS_Set :: bit_set[runtime.Odin_OS_Type]
// TODO: update this
SUPPORTED_OS :: OS_Set{.Linux, .Darwin, .FreeBSD, .OpenBSD, .NetBSD}
#assert(ODIN_OS in SUPPORTED_OS)


Flags :: enum {
    Use_Context_Logger,
    Echo_Commands,
}
Flags_Set :: bit_set[Flags]


create_logger :: proc() -> log.Logger {
    logger_proc :: proc(
        logger_data: rawptr,
        level: log.Level,
        text: string,
        options: log.Options,
        loc: Loc,
    ) {
        _log_no_flag(level, text, loc)
    }
    return log.Logger{logger_proc, nil, log.Level.Debug, {}}
}

log_fatal :: proc(args: ..any, sep: string = " ", loc := #caller_location) {
    _log_sep(.Fatal, sep, loc, ..args)
}
log_fatalf :: proc(fmt: string, args: ..any, loc := #caller_location) {
    _log_fmt(.Fatal, fmt, loc, ..args)
}
log_error :: proc(args: ..any, sep: string = " ", loc := #caller_location) {
    _log_sep(.Error, sep, loc, ..args)
}
log_errorf :: proc(fmt: string, args: ..any, loc := #caller_location) {
    _log_fmt(.Error, fmt, loc, ..args)
}
log_warn :: proc(args: ..any, sep: string = " ", loc := #caller_location) {
    _log_sep(.Warning, sep, loc, ..args)
}
log_warnf :: proc(fmt: string, args: ..any, loc := #caller_location) {
    _log_fmt(.Warning, fmt, loc, ..args)
}
log_info :: proc(args: ..any, sep: string = " ", loc := #caller_location) {
    _log_sep(.Info, sep, loc, ..args)
}
log_infof :: proc(fmt: string, args: ..any, loc := #caller_location) {
    _log_fmt(.Info, fmt, loc, ..args)
}
log_debug :: proc(args: ..any, sep: string = " ", loc := #caller_location) {
    _log_sep(.Debug, sep, loc, ..args)
}
log_debugf :: proc(fmt: string, args: ..any, loc := #caller_location) {
    _log_fmt(.Debug, fmt, loc, ..args)
}


Exit :: _Exit
Signal :: _Signal
Process_Exit :: _Process_Exit
Process_Handle :: _Process_Handle

Process :: struct {
    using _impl:    _Process,
    execution_time: time.Time,
}

process_handle :: proc(self: Process) -> Process_Handle {
    return _process_handle(self)
}

process_wait :: proc(
    self: Process,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    result: Process_Result,
    ok: bool,
) {
    log: Maybe(string)
    result, log, ok = _process_wait(self, allocator, loc)
    if log != nil {
        log_infof("Log from %v:\n%s", self.pid, log.?, loc = loc)
    }
    return
}

process_wait_many :: proc(
    selves: []Process,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    results: []Process_Result,
    ok: bool,
) {
    return _process_wait_many(selves, allocator, loc)
}


Process_Result :: struct {
    exit:     Process_Exit, // nil on success
    duration: time.Duration,
    stdout:   string, // both are "" if run_prog_* is not capturing
    stderr:   string, // I didn't make them both Maybe() for "convenience" when accessing them
}

process_result_destroy :: proc(self: ^Process_Result, loc := #caller_location) {
    _process_result_destroy(self, loc)
}

process_result_destroy_many :: proc(selves: []Process_Result, loc := #caller_location) {
    _process_result_destroy_many(selves, loc)
}


// FIXME: *some* programs that read from stdin may hang if called with .Silent or .Capture
Run_Prog_Option :: enum {
    Share,
    Silent,
    Capture,
}

run_prog_async :: proc {
    run_prog_async_unchecked,
    run_prog_async_checked,
}

run_prog_sync :: proc {
    run_prog_sync_unchecked,
    run_prog_sync_checked,
}

run_prog_async_unchecked :: proc(
    prog: string,
    args: []string = nil,
    option: Run_Prog_Option = .Share,
    loc := #caller_location,
) -> (
    process: Process,
    ok: bool,
) {
    return _run_prog_async_unchecked(prog, args, option, loc)
}

// DOCS: `process` is empty or {} if `cmd` is not found
run_prog_async_checked :: proc(
    prog: Program,
    args: []string = nil,
    option: Run_Prog_Option = .Share,
    require: bool = true,
    loc := #caller_location,
) -> (
    process: Process,
    ok: bool,
) {
    if !check_program(prog, require, loc) {
        return {}, !require
    }
    return _run_prog_async_unchecked(prog.name, args, option, loc)
}

run_prog_sync_unchecked :: proc(
    prog: string,
    args: []string = nil,
    option: Run_Prog_Option = .Share,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    result: Process_Result,
    ok: bool,
) {
    process := run_prog_async_unchecked(prog, args, option, loc) or_return
    return process_wait(process, allocator, loc)
}

// `result` is empty or {} if `cmd` is not found
run_prog_sync_checked :: proc(
    prog: Program,
    args: []string = nil,
    option: Run_Prog_Option = .Share,
    allocator := context.allocator,
    require: bool = true,
    loc := #caller_location,
) -> (
    result: Process_Result,
    ok: bool,
) {
    if !check_program(prog, require, loc) {
        return {}, !require
    }
    process := run_prog_async_unchecked(prog.name, args, option, loc) or_return
    return process_wait(process, allocator, loc)
}


// DOCS: tell the user to manually init and destroy process tracker if they want to store process log
process_tracker_init :: proc() -> (ok: bool) {
    if g_process_tracker_initialised {
        return
    }
    ok = _process_tracker_init()
    g_process_tracker_initialised = ok
    return
}

process_tracker_destroy :: proc() -> (ok: bool) {
    if !g_process_tracker_initialised {
        return
    }
    ok = _process_tracker_destroy()
    g_process_tracker_initialised = !ok
    return
}


Program :: struct {
    found: bool,
    name:  string,
    //full_path: string, // would require allocation
}

// DOCS: `ok` is always true if not `required`
@(require_results)
program :: proc(
    $name: string,
    required: bool = false,
    loc := #caller_location,
) -> (
    prog: Program,
    ok: bool,
) #optional_ok {
    flags_temp := g_flags
    disable_default_flags({.Echo_Commands})
    found := _program(name, loc)
    g_flags = flags_temp
    if !found {
        msg :: "Failed to find `" + name + "`"
        if required {
            log_error(msg, loc = loc)
        } else {
            log_warn(msg, loc = loc)
        }
    }
    return {name = name, found = found}, !(required && !found)
}

@(require_results)
check_program :: proc(
    prog: Program,
    require: bool = true,
    loc := #caller_location,
) -> (
    found: bool,
) {
    if !prog.found {
        msg := fmt.tprintf("`%v` does not exist", prog.name)
        if require {
            log_error(msg, loc = loc)
        } else {
            log_warn(msg, loc = loc)
        }
        return
    }
    return true
}


get_default_flags :: proc() -> Flags_Set {
    return g_flags
}

set_default_flags :: proc(flags: Flags_Set) {
    g_flags = flags
}

enable_default_flags :: proc(flags: Flags_Set) {
    g_flags += flags
}

disable_default_flags :: proc(flags: Flags_Set) {
    g_flags -= flags
}

