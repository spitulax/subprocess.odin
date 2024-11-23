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
    Echo_Commands_Debug,
}
Flags_Set :: bit_set[Flags]


Error :: union {
    // `program_check`, `run_prog_*_checked`
    Program_Not_Found,

    // `process_wait*`
    Process_Cannot_Exit,
    Process_Not_Executed,

    // `run_prog*`
    Spawn_Failed,

    // `process_tracker_init*`
    Process_Tracker_Error,

    // Target specific stuff
    Internal_Error,
}

Program_Not_Found :: struct {
    name: string,
}

Process_Cannot_Exit :: struct {
    handle: Process_Handle,
    errno:  Errno,
}

Process_Not_Executed :: struct {
    handle: Process_Handle,
}

Spawn_Failed :: struct {
    errno: Errno,
}

Process_Tracker_Error :: _Process_Tracker_Error

Internal_Error :: _Internal_Error

strerror :: proc(err: Error, alloc := context.allocator) -> string {
    context.allocator = alloc
    switch v in err {
    case Program_Not_Found:
        return fmt.aprintf("Cannot find `%v`", v.name)
    case Process_Cannot_Exit:
        return fmt.aprintf("Process %v cannot exit: %s", v.handle, strerrno(v.errno))
    case Process_Not_Executed:
        return fmt.aprintf("Process %v did not execute the command successfully", v.handle)
    case Spawn_Failed:
        return fmt.aprintf("Failed to spawn child process: %s", strerrno(v.errno))
    case Process_Tracker_Error:
        return process_tracker_strerror(v)
    case Internal_Error:
        return internal_strerror(v)
    }
    unreachable()
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
    err: Error,
) {
    log: Maybe(string)
    result, log, err = _process_wait(self, allocator, loc)
    if log != nil {
        log_infof("Log from %v:\n%s", self.pid, log.?, loc = loc)
    }
    return
}

process_wait_many :: proc(
    selves: []Process,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    results: []Process_Result,
    errs: []Error,
    ok: bool,
) {
    ok = true
    defer if !ok {
        results = nil
    }
    results = make([]Process_Result, len(selves), alloc, loc)
    errs = make([]Error, len(selves), alloc, loc)
    for process, i in selves {
        process_result, process_err := process_wait(process, alloc, loc)
        ok &&= (process_err != nil)
        results[i] = process_result
        errs[i] = process_err
    }
    return
}


Process_Result :: struct {
    exit:     Process_Exit, // nil on success
    duration: time.Duration,
    stdout:   string, // both are "" if run_prog_* is not capturing
    stderr:   string, // I didn't make them both Maybe() for "convenience" when accessing them
}

process_result_destroy :: proc(self: ^Process_Result, loc := #caller_location) {
    delete(self.stdout, loc = loc)
    delete(self.stderr, loc = loc)
    self^ = {}
}

process_result_destroy_many :: proc(selves: []Process_Result, loc := #caller_location) {
    for &result in selves {
        process_result_destroy(&result, loc)
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
        err = Program_Not_Found{prog.name}
        return
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
    err: Error,
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
    loc := #caller_location,
) -> (
    result: Process_Result,
    err: Error,
) {
    if !prog.found {
        err = Program_Not_Found{prog.name}
        return
    }
    process := run_prog_async_unchecked(prog.name, args, option, loc) or_return
    return process_wait(process, allocator, loc)
}


// DOCS: tell the user to manually init and destroy process tracker if they want to store process log
process_tracker_init :: proc() -> (err: Process_Tracker_Error) {
    if g_process_tracker_initialised {
        return
    }
    err = _process_tracker_init()
    g_process_tracker_initialised = err == nil
    return
}

process_tracker_destroy :: proc() -> (err: Process_Tracker_Error) {
    if !g_process_tracker_initialised {
        return
    }
    err = _process_tracker_destroy()
    g_process_tracker_initialised = err != nil
    return
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
        err = Program_Not_Found{name}
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

