package subprocess

// MAYBE: Add a function that invokes the respective system's shell like libc's `system()`

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:time"


OS_Set :: bit_set[runtime.Odin_OS_Type]
// TODO: update this
POSIX_OS :: OS_Set{.Linux, .Darwin, .FreeBSD, .OpenBSD, .NetBSD} // use implementations from `subprocess_posix.odin`
SUPPORTED_OS :: POSIX_OS
#assert(ODIN_OS in SUPPORTED_OS)


Flags :: enum {
    Use_Context_Logger,
    Echo_Commands,
    Echo_Commands_Debug,
}
Flags_Set :: bit_set[Flags]


Error :: union #shared_nil {
    General_Error,

    // Target specific stuff
    Internal_Error,
}

General_Error :: enum u8 {
    None = 0,

    // `program_check`, `run_prog_*_checked`
    Program_Not_Found,

    // `process_wait*`
    Process_Cannot_Exit,
    Program_Not_Executed,
    Program_Execution_Failed,

    // `run_prog*`
    Spawn_Failed,
}

Internal_Error :: _Internal_Error

// DOCS:
// ```
// result, err := run_prog_sync("command")
// // or ...
// result = unwrap(run_prog_sync("command")) // prints the error using `log_error`
// ```
unwrap :: proc(ret: $T, err: Error, loc := #caller_location) -> (res: T, ok: bool) #optional_ok {
    if err != nil {
        log_error(err, loc = loc)
        ok = false
        return
    }
    return ret, true
}


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
    handle:         Process_Handle,
    execution_time: time.Time,
}

process_wait :: proc(
    self: Process,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    result: Process_Result,
    err: Error,
) {
    log: Maybe(string)
    result, log, err = _process_wait(self, alloc, loc)
    // TODO: return the string instead of printing it
    if log != nil {
        log_infof("Log from %v:\n%s", self.handle, log.?, loc = loc)
    }
    return
}

process_wait_many :: proc(
    selves: []Process,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    res: #soa[]struct {
        result: Process_Result,
        err:    Error,
    },
) {
    res = make_soa_slice(type_of(res), len(selves), alloc, loc)
    for process, i in selves {
        process_result, process_err := process_wait(process, alloc, loc)
        res[i].result = process_result
        res[i].err = process_err
    }
    return
}


Process_Result :: struct {
    exit:     Process_Exit, // nil on success
    duration: time.Duration,
    stdout:   string, // both are "" if run_prog_* is not capturing
    stderr:   string, // I didn't make them both Maybe() for "convenience" when accessing them
}

process_result_destroy :: proc(
    self: ^Process_Result,
    alloc := context.allocator,
    loc := #caller_location,
) {
    delete(self.stdout, alloc, loc)
    delete(self.stderr, alloc, loc)
    self^ = {}
}

process_result_destroy_many :: proc(
    selves: []Process_Result,
    alloc := context.allocator,
    loc := #caller_location,
) {
    for &result in selves {
        process_result_destroy(&result, alloc, loc)
    }
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
    err: Error,
) {
    return _run_prog_async_unchecked(prog, args, option, loc)
}

// DOCS: `process` is empty or {} if `cmd` is not found
run_prog_async_checked :: proc(
    prog: Program,
    args: []string = nil,
    option: Run_Prog_Option = .Share,
    loc := #caller_location,
) -> (
    process: Process,
    err: Error,
) {
    if !prog.found {
        err = General_Error.Program_Not_Found
        return
    }
    return _run_prog_async_unchecked(prog.name, args, option, loc)
}

run_prog_sync_unchecked :: proc(
    prog: string,
    args: []string = nil,
    option: Run_Prog_Option = .Share,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    result: Process_Result,
    err: Error,
) {
    process := run_prog_async_unchecked(prog, args, option, loc) or_return
    return process_wait(process, alloc, loc)
}

// `result` is empty or {} if `cmd` is not found
run_prog_sync_checked :: proc(
    prog: Program,
    args: []string = nil,
    option: Run_Prog_Option = .Share,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    result: Process_Result,
    err: Error,
) {
    if !prog.found {
        err = General_Error.Program_Not_Found
        return
    }
    process := run_prog_async_unchecked(prog.name, args, option, loc) or_return
    return process_wait(process, alloc, loc)
}


Program :: struct {
    found: bool,
    name:  string,
    //full_path: string, // would require allocation
}

@(require_results)
program :: proc($name: string, loc := #caller_location) -> Program {
    prog, _ := program_check(name, loc)
    return prog
}

@(require_results)
program_check :: proc($name: string, loc := #caller_location) -> (prog: Program, err: Error) {
    flags_temp := g_flags
    disable_default_flags({.Echo_Commands, .Echo_Commands_Debug})
    found := _program(name, loc)
    g_flags = flags_temp
    if !found {
        err = General_Error.Program_Not_Found
    }
    return {name = name, found = found}, err
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

