package subprocess

import "base:runtime"
import "core:fmt"
import "core:time"


OS_Set :: bit_set[runtime.Odin_OS_Type]
// TODO: update this
SUPPORTED_OS :: OS_Set{.Linux}
#assert(ODIN_OS in SUPPORTED_OS)


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
    return _process_wait(self, allocator, loc)
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

// `process` is empty or {} if `cmd` is not found
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


Program :: struct {
    found: bool,
    name:  string,
    //full_path: string, // would require allocation
}

@(require_results)
program :: proc($name: string, loc := #caller_location) -> Program {
    return _program(name, loc)
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


set_use_context_logger :: proc(use: bool = true) {
    g_use_context_logger = use
}

