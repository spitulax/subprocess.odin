package subprocess

// MAYBE: store the location of where `run_prog*` is called in `Process`
// then store it and the location of `process_wait*` in `Process_Result`

import "base:intrinsics"
import "core:log"
import "core:strings"
import "core:time"


// Use implementations from `subprocess_posix.odin`.
POSIX_OS :: OS_Set{.Linux, .Darwin, .FreeBSD, .OpenBSD, .NetBSD}
// Uses implementations from `subprocess_windows.odin`.
WINDOWS_OS :: OS_Set{.Windows}


Flags :: enum u8 {
    // Use the logger from context.logger instead of subprocess.odin's own logger.
    Use_Context_Logger,
    // Logs the command that is running (log level = info).
    Echo_Commands,
    // Logs the command that is running (log level = debug).
    Echo_Commands_Debug,
}

// Sets the behaviour of the library.
Flags_Set :: bit_set[Flags]


Error :: union #shared_nil {
    General_Error,
    Internal_Error,
}

General_Error :: enum u8 {
    None = 0,
    // Program was not found in in PATH variable or relative from the current directory.
    Program_Not_Found,
    // Process could not exit normally.
    Process_Cannot_Exit,
    // The calling procedure returned before the program is executed.
    Program_Not_Executed,
    // The system failed to spawn the process.
    Spawn_Failed,
    // Failed to write into the pipe.
    Pipe_Write_Failed,
}

// Target-specific errors.
Internal_Error :: _Internal_Error

/*
Handle error in return values by logging it with `log_error`.

Example:
	result, err := run_prog_sync("command")
	// or ...
	result = unwrap(run_prog_sync("command")) // prints the error using `log_error`
*/
unwrap :: proc {
    unwrap_0,
    unwrap_1,
}

// See `unwrap`.
unwrap_0 :: proc(err: Error, loc := #caller_location) -> (ok: bool) {
    if err != nil {
        log_error(err, loc = loc)
        return false
    }
    return true
}

// See `unwrap`.
unwrap_1 :: proc(ret: $T, err: Error, loc := #caller_location) -> (res: T, ok: bool) #optional_ok {
    if err != nil {
        log_error(err, loc = loc)
        ok = false
        return
    }
    return ret, true
}


/*
Use subprocess.odin's logger procedures to create a logger.

Example:
	context.logger = create_logger()
	log.info("This is using subprocess.odin's logger")
*/
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


/*
Stores process exit status.
In POSIX OS, This could be either an exit code or a signal.
In Windows, This can only be an exit code.
*/
Process_Exit :: _Process_Exit
// Stores process handle or PID
Process_Handle :: _Process_Handle

// Checks if `exit` indicates a successful exit.
is_success :: proc(exit: Process_Exit) -> bool {
    return _is_success(exit)
}

// Stores data for running process.
Process :: struct {
    // The process handle or PID.
    handle:         Process_Handle,
    // The time the process starts being executed.
    execution_time: time.Time,
    // Is the process alive.
    alive:          bool,
    // The pipe to process' stdout.
    // nil if `Output_Option` is `Share` or `Silent`.
    stdout_pipe:    Maybe(Pipe),
    // The pipe to process' stdout.
    // nil if `Output_Option` is not `Capture`.
    stderr_pipe:    Maybe(Pipe),
    // The pipe to process' stdin.
    // nil if `Input_Option` is `Pipe`.
    stdin_pipe:     Maybe(Pipe),
}

/*
Wait for a `Process` to exit.
Allocates if `Process.stdout_pipe` and `Process.stderr_pipe` are not nil.
*/
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

/*
Wait for multiple `Process` to exit.
Stores the result and error for each `Process` in a SoA struct.

Example:
	results := process_wait_many(processes)
	for result in results {
	    result := result.result
	    err := result.err
	}
*/
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


// Stores the result of a `Process` that has exited.
Process_Result :: struct {
    // The exit status.
    exit:     Process_Exit,
    // The running duration.
    duration: time.Duration,
    // The contents of stdout.
    // Empty if `Process.stdout_pipe` is nil.
    stdout:   string,
    // The contents of stderr.
    // Empty if `Process.stderr_pipe` is nil.
    stderr:   string,
    // NOTE: I didn't make `stdout` and `stderr` Maybe() for "convenience" when accessing them
}

// Checks if a `Process_Result` indicates a successful exit.
process_result_success :: proc(self: Process_Result) -> bool {
    return is_success(self.exit)
}

// Deallocates a `Process_Result`.
process_result_destroy :: proc(
    self: ^Process_Result,
    alloc := context.allocator,
    loc := #caller_location,
) {
    delete(self.stdout, alloc, loc)
    delete(self.stderr, alloc, loc)
    self^ = {}
}

// Deallocates multiple `Process_Result`.
process_result_destroy_many :: proc(
    selves: []Process_Result,
    alloc := context.allocator,
    loc := #caller_location,
) {
    for &result in selves {
        process_result_destroy(&result, alloc, loc)
    }
}


// Controls how the process' output will be handled.
Output_Option :: enum u8 {
    // Inherit stdout and stderr from the parent process.
    Share,
    // Silence stdout and stderr.
    Silent,
    // Capture stdout and stderr.
    // Will assign to `Process.stdout_pipe` and `Process.stderr_pipe`.
    Capture,
    // Capture stdout and stderr combined.
    // Will just assign to `Process.stdout_pipe`.
    Capture_Combine,
}

// Controls how the process' input will be handled.
Input_Option :: enum u8 {
    // Inherit stdin from the parent process.
    Share,
    // Write nothing into stdin.
    Nothing,
    // Redirect stdin into a pipe.
    // Will assign to `Process.stdin_pipe`.
    // When the process is still running, `pipe_write` can be used to write data into the pipe.
    Pipe,
}

/*
Runs a program asynchronously.
The process will keep running in parallel until explicitly waited using `process_wait*`.

Inputs:
- prog: The program to run as a `Program` or a string. `unchecked` version accepts a string, `checked` version accepts a `Program`.
- args: Arguments to the program.
- out_opt: The `Output_Option`.
- in_opt: The `Input_Option`.
- inherit_env: Whether the process will inherit environment variables of the parent process.
- extra_env: Extra environment variables with a format of "key=value". If `inherit_env` is false, it is basically the only environment variables of the process.
*/
run_prog_async :: proc {
    run_prog_async_unchecked,
    run_prog_async_checked,
}

// Runs a program synchronously.
// The procedure will wait for the process.
// See `run_prog_async` for informations about the parameters.
run_prog_sync :: proc {
    run_prog_sync_unchecked,
    run_prog_sync_checked,
}

// See `run_prog_async`.
run_prog_async_unchecked :: proc(
    prog: string,
    args: []string = {},
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    inherit_env: bool = true,
    extra_env: []string = {},
    loc := #caller_location,
) -> (
    process: Process,
    err: Error,
) {
    return _run_prog_async_unchecked(prog, args, out_opt, in_opt, inherit_env, extra_env, loc)
}

// See `run_prog_async`.
run_prog_async_checked :: proc(
    prog: Program,
    args: []string = {},
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    inherit_env: bool = true,
    extra_env: []string = {},
    loc := #caller_location,
) -> (
    process: Process,
    err: Error,
) {
    if !prog.found {
        err = General_Error.Program_Not_Found
        return
    }
    return _run_prog_async_unchecked(prog.name, args, out_opt, in_opt, inherit_env, extra_env, loc)
}

// See `run_prog_sync`.
run_prog_sync_unchecked :: proc(
    prog: string,
    args: []string = {},
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    inherit_env: bool = true,
    extra_env: []string = {},
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    result: Process_Result,
    err: Error,
) {
    process := run_prog_async_unchecked(
        prog,
        args,
        out_opt,
        in_opt,
        inherit_env,
        extra_env,
        loc,
    ) or_return
    return process_wait(&process, alloc, loc)
}

// See `run_prog_sync`.
run_prog_sync_checked :: proc(
    prog: Program,
    args: []string = {},
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    inherit_env: bool = true,
    extra_env: []string = {},
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
    process := run_prog_async_unchecked(
        prog.name,
        args,
        out_opt,
        in_opt,
        inherit_env,
        extra_env,
        loc,
    ) or_return
    return process_wait(&process, alloc, loc)
}

/*
Runs a shell command asynchronously.
The process will keep running in parallel until explicitly waited using `process_wait*`.
In POSIX, it will use /bin/sh.
In Windows, it will use cmd.exe.
See `run_prog_async` for informations about the parameters.
*/
run_shell_async :: proc(
    cmd: string,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    inherit_env: bool = true,
    extra_env: []string = {},
    loc := #caller_location,
) -> (
    process: Process,
    err: Error,
) {
    return run_prog_async(SH, {CMD, cmd}, out_opt, in_opt, inherit_env, extra_env, loc)
}

/*
Runs a shell command synchronously.
The procedure will wait for the process.
In POSIX, it will use /bin/sh.
In Windows, it will use cmd.exe.
See `run_prog_async` for informations about the parameters.
*/
run_shell_sync :: proc(
    cmd: string,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    inherit_env: bool = true,
    extra_env: []string = {},
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    result: Process_Result,
    err: Error,
) {
    return run_prog_sync(SH, {CMD, cmd}, out_opt, in_opt, inherit_env, extra_env, alloc, loc)
}


// Stores representation of an executable program.
Program :: struct {
    // Is the program found.
    found: bool,
    // The name of the program (could be an executable name or a path, see `program`).
    name:  string,
}

/*
Returns a program from `name`.
`name` could be an executable name, which in this case it will search from the PATH variable.
`name` could also be a path to an executable.
*/
@(require_results)
program :: proc(name: string, loc := #caller_location) -> Program {
    prog, _ := program_check(name, loc)
    return prog
}

// The same as `program`, but returns up the error.
@(require_results)
program_check :: proc(name: string, loc := #caller_location) -> (prog: Program, err: Error) {
    flags_temp := g_flags
    default_flags_disable({.Echo_Commands, .Echo_Commands_Debug})
    err = _program(name, loc)
    g_flags = flags_temp
    return Program{err == nil, name}, err
}


// Stores a program with its arguments.
Command :: struct {
    prog:  Program,
    args:  [dynamic]string,
    alloc: Alloc,
}

/*
Make a `Command`.
`prog` version accepts a `Program`, otherwise it accepts the program name.
*/
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

// See `command_make`.
@(require_results)
command_make_none :: proc(
    prog_name: string,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    res: Command,
    err: Error,
) {
    return _command_make(program_check(prog_name, loc) or_return, 0, 0, alloc, loc), nil
}

// See `command_make`.
@(require_results)
command_make_len :: proc(
    prog_name: string,
    len: int,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    res: Command,
    err: Error,
) {
    return _command_make(program_check(prog_name, loc) or_return, len, len, alloc, loc), nil
}

// See `command_make`.
@(require_results)
command_make_len_cap :: proc(
    prog_name: string,
    len, cap: int,
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    res: Command,
    err: Error,
) {
    return _command_make(program_check(prog_name, loc) or_return, len, cap, alloc, loc), nil
}

// See `command_make`.
@(require_results)
command_make_prog_none :: proc(
    prog: Program,
    alloc := context.allocator,
    loc := #caller_location,
) -> Command {
    return _command_make(prog, 0, 0, alloc, loc)
}

// See `command_make`.
@(require_results)
command_make_prog_len :: proc(
    prog: Program,
    len: int,
    alloc := context.allocator,
    loc := #caller_location,
) -> Command {
    return _command_make(prog, len, len, alloc, loc)
}

// See `command_make`.
@(require_results)
command_make_prog_len_cap :: proc(
    prog: Program,
    len, cap: int,
    alloc := context.allocator,
    loc := #caller_location,
) -> Command {
    return _command_make(prog, len, cap, alloc, loc)
}

// Appends to the arguments.
command_append :: proc {
    command_append_one,
    command_append_many,
}

// See `command_append`.
command_append_one :: proc(self: ^Command, arg: string, loc := #caller_location) {
    append(&self.args, arg, loc)
}

// See `command_append`.
command_append_many :: proc(self: ^Command, args: ..string, loc := #caller_location) {
    append(&self.args, ..args, loc = loc)
}

// Injects at the arguments.
command_inject_at :: proc {
    command_inject_one_at,
    command_inject_many_at,
}

// See `command_inject_at`.
command_inject_one_at :: proc(self: ^Command, index: int, arg: string, loc := #caller_location) {
    inject_at(&self.args, index, arg, loc)
}

// See `command_inject_at`.
command_inject_many_at :: proc(
    self: ^Command,
    index: int,
    args: ..string,
    loc := #caller_location,
) {
    inject_at(&self.args, index, ..args, loc = loc)
}

// Assigns to an argument.
command_assign_at :: proc {
    command_assign_one_at,
    command_assign_many_at,
}

// See `command_assign_at`.
command_assign_one_at :: proc(self: ^Command, index: int, arg: string, loc := #caller_location) {
    assign_at(&self.args, index, arg, loc)
}

// See `command_assign_at`.
command_assign_many_at :: proc(
    self: ^Command,
    index: int,
    args: ..string,
    loc := #caller_location,
) {
    assign_at(&self.args, index, ..args, loc = loc)
}

// Clear the arguments.
command_clear :: proc(self: ^Command) {
    clear(&self.args)
}

// Destroy a `Command`.
command_destroy :: proc(self: ^Command, loc := #caller_location) {
    command_clear(self)
    delete(self.args, loc)
}

/*
Run a `Command` synchronously. See `run_prog_sync`.
See `run_prog_async` for informations about the parameters.
*/
command_run_sync :: proc(
    self: Command,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    inherit_env: bool = true,
    extra_env: []string = {},
    alloc := context.allocator,
    loc := #caller_location,
) -> (
    result: Process_Result,
    err: Error,
) {
    return run_prog_sync(
        self.prog,
        self.args[:],
        out_opt,
        in_opt,
        inherit_env,
        extra_env,
        alloc,
        loc,
    )
}

/*
Run a `Command` asynchronously. See `run_prog_async`.
See `run_prog_async` for informations about the parameters.
*/
command_run_async :: proc(
    self: Command,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
    inherit_env: bool = true,
    extra_env: []string = {},
    loc := #caller_location,
) -> (
    process: Process,
    err: Error,
) {
    return run_prog_async(self.prog, self.args[:], out_opt, in_opt, inherit_env, extra_env, loc)
}


// Stores a pipe. The implementation depends on the target.
Pipe :: _Pipe

/*
Write to a `Pipe`.

Inputs:
- `send_newline`: Append the data with a newline (0xA).
*/
pipe_write :: proc {
    pipe_write_buf,
    pipe_write_string,
}

// See `pipe_write`.
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

// See `pipe_write`.
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


// Returns the flags.
@(require_results)
default_flags :: proc() -> Flags_Set {
    return g_flags
}

// Sets the flags.
default_flags_set :: proc(flags: Flags_Set) {
    g_flags = flags
}

// Enables some flags.
default_flags_enable :: proc(flags: Flags_Set) {
    g_flags += flags
}

// Disable some flags.
default_flags_disable :: proc(flags: Flags_Set) {
    g_flags -= flags
}

