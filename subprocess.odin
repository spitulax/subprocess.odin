package subprocess

// TODO: `program` doesn't work with file paths in Windows
// TODO: Specify additional environment variable in `run_*` functions
// TODO: Add option to not inherit environment
// MAYBE: store the location of where `run_prog*` is called in `Process`
// then store it and the location of `process_wait*` in `Process_Result`

import "base:intrinsics"
import "core:log"
import "core:strings"
import "core:time"


POSIX_OS :: OS_Set{.Linux, .Darwin, .FreeBSD, .OpenBSD, .NetBSD} // use implementations from `subprocess_posix.odin`
WINDOWS_OS :: OS_Set{.Windows} // uses implementations from `subprocess_windows.odin`
SUPPORTED_OS :: POSIX_OS


Flags :: enum u8 {
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
    Program_Not_Found,
    Process_Cannot_Exit,
    Program_Not_Executed,
    Spawn_Failed,
    Pipe_Write_Failed,
}

Internal_Error :: _Internal_Error

// DOCS:
// ```
// result, err := run_prog_sync("command")
// // or ...
// result = unwrap(run_prog_sync("command")) // prints the error using `log_error`
// ```
unwrap :: proc {
    unwrap_0,
    unwrap_1,
}

unwrap_0 :: proc(err: Error, loc := #caller_location) -> (ok: bool) {
    if err != nil {
        log_error(err, loc = loc)
        return false
    }
    return true
}

unwrap_1 :: proc(ret: $T, err: Error, loc := #caller_location) -> (res: T, ok: bool) #optional_ok {
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


Process_Exit :: _Process_Exit
Process_Handle :: _Process_Handle

is_success :: proc(exit: Process_Exit) -> bool {
    return _is_success(exit)
}

Process :: struct {
    handle:         Process_Handle,
    execution_time: time.Time,
    alive:          bool,
    stdout_pipe:    Maybe(Pipe),
    stderr_pipe:    Maybe(Pipe),
    stdin_pipe:     Maybe(Pipe),
}

process_wait :: proc(
    self: ^Process,
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
    for &process, i in selves {
        process_result, process_err := process_wait(&process, alloc, loc)
        res[i].result = process_result
        res[i].err = process_err
    }
    return
}


Process_Result :: struct {
    exit:     Process_Exit,
    duration: time.Duration,
    // I didn't make them both Maybe() for "convenience" when accessing them
    stdout:   string, // stdout and stderr are empty if run_prog_* was called with .Capture
    stderr:   string, // but stderr is empty if run_prog_* was called with .Capture_Combine
}

process_result_success :: proc(self: Process_Result) -> bool {
    return is_success(self.exit)
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


Output_Option :: enum u8 {
    Share,
    Silent,
    Capture, // separate stdout and stderr
    Capture_Combine, // combine stdout and stderr
}

Input_Option :: enum u8 {
    Share,
    Nothing, // send nothing
    Pipe, // return the stdin pipe
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
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    loc := #caller_location,
) -> (
    process: Process,
    err: Error,
) {
    return _run_prog_async_unchecked(prog, args, out_opt, in_opt, loc)
}

// DOCS: `process` is empty or {} if `cmd` is not found
run_prog_async_checked :: proc(
    prog: Program,
    args: []string = nil,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    loc := #caller_location,
) -> (
    process: Process,
    err: Error,
) {
    if !prog.found {
        err = General_Error.Program_Not_Found
        return
    }
    return _run_prog_async_unchecked(prog.name, args, out_opt, in_opt, loc)
}

run_prog_sync_unchecked :: proc(
    prog: string,
    args: []string = nil,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    result: Process_Result,
    err: Error,
) {
    process := run_prog_async_unchecked(prog, args, out_opt, in_opt, loc) or_return
    return process_wait(&process, alloc, loc)
}

// `result` is empty or {} if `cmd` is not found
run_prog_sync_checked :: proc(
    prog: Program,
    args: []string = nil,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
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
    process := run_prog_async_unchecked(prog.name, args, out_opt, in_opt, loc) or_return
    return process_wait(&process, alloc, loc)
}

run_shell_async :: proc(
    cmd: string,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    loc := #caller_location,
) -> (
    process: Process,
    err: Error,
) {
    return run_prog_async(SH, {CMD, cmd}, out_opt, in_opt, loc)
}

run_shell_sync :: proc(
    cmd: string,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    result: Process_Result,
    err: Error,
) {
    return run_prog_sync(SH, {CMD, cmd}, out_opt, in_opt, alloc, loc)
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
    // TODO: make `_program` return up the error
    found := _program(name, loc)
    g_flags = flags_temp
    if !found {
        err = General_Error.Program_Not_Found
    }
    return Program{found, name}, err
}


Command :: struct {
    prog:  Program,
    args:  [dynamic]string,
    alloc: Alloc,
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
    return Command{prog = prog, args = make([dynamic]string, len, cap, alloc, loc), alloc = alloc}
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

command_destroy :: proc(self: ^Command, loc := #caller_location) {
    command_clear(self)
    delete(self.args, loc)
}

command_run_sync :: proc(
    self: Command,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    loc := #caller_location,
) -> (
    result: Process_Result,
    err: Error,
) {
    return run_prog_sync(self.prog, self.args[:], out_opt, in_opt, self.alloc, loc)
}

command_run_async :: proc(
    self: Command,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    loc := #caller_location,
) -> (
    process: Process,
    err: Error,
) {
    return run_prog_async(self.prog, self.args[:], out_opt, in_opt, loc)
}


Pipe :: _Pipe

pipe_write :: proc {
    pipe_write_buf,
    pipe_write_string,
}

pipe_write_buf :: proc(
    self: Pipe,
    buf: []byte,
    send_newline: bool = true,
) -> (
    n: int,
    err: Error,
) {
    if send_newline {
        nl_buf := make([]byte, len(buf) + len(NL))
        defer delete(nl_buf)
        copy_slice(nl_buf, buf)
        nl := NL
        for i in 0 ..< len(NL) {
            nl_buf[len(buf) + i] = nl[i]
        }
        return _pipe_write_buf(self, nl_buf)
    }
    return _pipe_write_buf(self, buf)
}

pipe_write_string :: proc(
    self: Pipe,
    str: string,
    send_newline: bool = true,
) -> (
    n: int,
    err: Error,
) {
    if send_newline {
        nl_sb := strings.builder_make(0, len(str) + len(NL))
        defer strings.builder_destroy(&nl_sb)
        strings.write_string(&nl_sb, str)
        strings.write_string(&nl_sb, NL)
        return _pipe_write_string(self, strings.to_string(nl_sb))
    }
    return _pipe_write_string(self, str)
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

