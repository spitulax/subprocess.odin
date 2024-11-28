package subprocess

// TODO: Specify additional environment variable in `run_*` functions
// TODO: Support Windows
// TODO: Make sending to stdin without user input possible
// MAYBE: Add a function that invokes the respective system's shell like libc's `system()`

import "base:intrinsics"
import "core:log"
import "core:time"


POSIX_OS :: OS_Set{.Linux, .Darwin, .FreeBSD, .OpenBSD, .NetBSD} // use implementations from `subprocess_posix.odin`
SUPPORTED_OS :: POSIX_OS


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


@(require_results)
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
    result, err = _process_wait(self, alloc, loc)
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
    default_flags_disable({.Echo_Commands, .Echo_Commands_Debug})
    found := _program(name, loc)
    g_flags = flags_temp
    if !found {
        err = General_Error.Program_Not_Found
    }
    return Program{found, name}, err
}


Command :: struct {
    prog:              Program,
    args:              [dynamic]string,
    results:           [dynamic]Process_Result,
    running_processes: [dynamic]Process,
    alloc:             Alloc,
}

command_make :: proc {
    command_make_none,
    command_make_len,
    command_make_len_cap,
    command_make_prog_none,
    command_make_prog_len,
    command_make_prog_len_cap,
}

@(private)
_command_make :: proc(prog: Program, len, cap: int, alloc: Alloc, loc: Loc) -> Command {
    return Command {
        prog = prog,
        args = make([dynamic]string, len, cap, alloc, loc),
        results = make([dynamic]Process_Result, alloc, loc),
        running_processes = make([dynamic]Process, alloc, loc),
        alloc = alloc,
    }
}

@(require_results)
command_make_none :: proc(
    $prog_name: string,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    res: Command,
    err: Error,
) {
    return _command_make(program_check(prog_name, loc) or_return, 0, 0, alloc, loc), nil
}

@(require_results)
command_make_len :: proc(
    $prog_name: string,
    len: int,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    res: Command,
    err: Error,
) {
    return _command_make(program_check(prog_name, loc) or_return, len, len, alloc, loc), nil
}

@(require_results)
command_make_len_cap :: proc(
    $prog_name: string,
    len, cap: int,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    res: Command,
    err: Error,
) {
    return _command_make(program_check(prog_name, loc) or_return, len, cap, alloc, loc), nil
}

@(require_results)
command_make_prog_none :: proc(
    prog: Program,
    alloc := context.allocator,
    loc := #caller_location,
) -> Command {
    return _command_make(prog, 0, 0, alloc, loc)
}

@(require_results)
command_make_prog_len :: proc(
    prog: Program,
    len: int,
    alloc := context.allocator,
    loc := #caller_location,
) -> Command {
    return _command_make(prog, len, len, alloc, loc)
}

@(require_results)
command_make_prog_len_cap :: proc(
    prog: Program,
    len, cap: int,
    alloc := context.allocator,
    loc := #caller_location,
) -> Command {
    return _command_make(prog, len, cap, alloc, loc)
}

command_append :: proc {
    command_append_one,
    command_append_many,
}

command_append_one :: proc(self: ^Command, arg: string, loc := #caller_location) {
    append(&self.args, arg, loc)
}

command_append_many :: proc(self: ^Command, args: ..string, loc := #caller_location) {
    append(&self.args, ..args, loc = loc)
}

command_inject_at :: proc {
    command_inject_one_at,
    command_inject_many_at,
}

command_inject_one_at :: proc(self: ^Command, index: int, arg: string, loc := #caller_location) {
    inject_at(&self.args, index, arg, loc)
}

command_inject_many_at :: proc(
    self: ^Command,
    index: int,
    args: ..string,
    loc := #caller_location,
) {
    inject_at(&self.args, index, ..args, loc = loc)
}

command_assign_at :: proc {
    command_assign_one_at,
    command_assign_many_at,
}

command_assign_one_at :: proc(self: ^Command, index: int, arg: string, loc := #caller_location) {
    assign_at(&self.args, index, arg, loc)
}

command_assign_many_at :: proc(
    self: ^Command,
    index: int,
    args: ..string,
    loc := #caller_location,
) {
    assign_at(&self.args, index, ..args, loc = loc)
}

command_clear :: proc(self: ^Command) {
    clear(&self.args)
}

command_wait_all :: proc(
    self: ^Command,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    res: #soa[]struct {
        result: ^Process_Result,
        err:    Error,
    },
) {
    res = make_soa_slice(type_of(res), len(self.running_processes), alloc, loc)
    for process, i in self.running_processes {
        process_result, process_err := process_wait(process, self.alloc, loc)
        append(&self.results, process_result, loc)
        res[i].result = &self.results[len(self.results) - 1]
        res[i].err = process_err
    }
    clear(&self.running_processes)
    return
}

command_destroy :: proc(self: ^Command, loc := #caller_location) -> Error {
    command_clear(self)
    command_destroy_results(self, loc)
    {
        res := command_wait_all(self)
        defer delete(res)
        for x in res {
            if x.err != nil {
                return x.err
            }
        }
    }

    delete(self.args, loc)
    delete(self.results, loc)
    delete(self.running_processes, loc)

    return nil
}

command_destroy_results :: proc(self: ^Command, loc := #caller_location) {
    process_result_destroy_many(self.results[:], self.alloc, loc)
    clear(&self.results)
}

command_run_sync :: proc(
    self: ^Command,
    option: Run_Prog_Option = .Share,
    loc := #caller_location,
) -> (
    result: ^Process_Result,
    err: Error,
) {
    append(
        &self.results,
        run_prog_sync(self.prog, self.args[:], option, self.alloc, loc) or_return,
        loc,
    )
    return &self.results[len(self.results) - 1], nil
}

command_run_async :: proc(
    self: ^Command,
    option: Run_Prog_Option = .Share,
    loc := #caller_location,
) -> (
    process: ^Process,
    err: Error,
) {
    append(
        &self.running_processes,
        run_prog_async(self.prog, self.args[:], option, loc) or_return,
        loc,
    )
    return &self.running_processes[len(self.running_processes) - 1], nil
}


@(require_results)
default_flags :: proc() -> Flags_Set {
    return g_flags
}

default_flags_set :: proc(flags: Flags_Set) {
    g_flags = flags
}

default_flags_enable :: proc(flags: Flags_Set) {
    g_flags += flags
}

default_flags_disable :: proc(flags: Flags_Set) {
    g_flags -= flags
}

