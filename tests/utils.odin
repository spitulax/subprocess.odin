package tests

import lib ".."
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:testing"
import "core:time"


REPO_ROOT :: #config(REPO_ROOT, "")


when ODIN_OS in lib.POSIX_OS {
    NL :: "\n"
    SH :: "sh"
    CMD :: "-c" // shell flag to execute the next argument as a command
} else when ODIN_OS in lib.WINDOWS_OS {
    NL :: "\r\n"
    SH :: "cmd.exe"
    CMD :: "/C"
}

trim_nl :: proc(s: string) -> string {
    return strings.trim_suffix(s, NL)
}

expect_success :: proc(t: ^testing.T, result: lib.Result, loc := #caller_location) -> bool {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    return testing.expect(
        t,
        lib.result_success(result),
        fmt.tprintf("exited with code %v", result.exit),
        loc = loc,
    )
}

expect_result :: proc {
    expect_result_nothing,
    expect_result_bytes,
    expect_result_string,
}

expect_result_nothing :: proc(
    t: ^testing.T,
    result: lib.Result,
    exit: Maybe(lib.Process_Exit) = nil,
    loc := #caller_location,
) -> (
    ok: bool,
) {
    if exit == nil {
        ok = expect_success(t, result, loc)
    } else {
        ok = testing.expect_value(t, result.exit, exit.?, loc)
    }
    ok = testing.expect(t, result.duration >= 0, "the result `duration` is not valid", loc = loc)
    return
}

expect_result_bytes :: proc(
    t: ^testing.T,
    result: lib.Result,
    stdout: []byte,
    stderr: []byte,
    exit: Maybe(lib.Process_Exit) = nil,
    loc := #caller_location,
) -> (
    ok: bool,
) {
    ok = expect_result_nothing(t, result, exit, loc)
    ok = testing.expectf(
        t,
        slice.equal(result.stdout, stdout),
        "expected result.stdout to be %v \"%s\", got %v \"%s\"",
        stdout,
        string(stdout),
        result.stdout,
        string(result.stdout),
        loc = loc,
    )
    ok = testing.expectf(
        t,
        slice.equal(result.stderr, stderr),
        "expected result.stderr to be %v \"%s\", got %v \"%s\"",
        stderr,
        string(stderr),
        result.stderr,
        string(result.stderr),
        loc = loc,
    )
    return ok
}

expect_result_string :: proc(
    t: ^testing.T,
    result: lib.Result,
    stdout: string,
    stderr: string,
    exit: Maybe(lib.Process_Exit) = nil,
    loc := #caller_location,
) -> (
    ok: bool,
) {
    return expect_result_bytes(
        t,
        result,
        transmute([]byte)stdout,
        transmute([]byte)stderr,
        exit,
        loc,
    )
}

expect_process :: proc(
    t: ^testing.T,
    process: lib.Process,
    loc := #caller_location,
) -> (
    ok: bool,
) {
    ok = testing.expect(t, process.alive, "the process is already dead", loc = loc)
    ok = testing.expect(
        t,
        time.time_to_unix(process.execution_time) >= 0,
        "the process `execution_time` is not valid",
        loc = loc,
    )

    stdout_pipe_ok := process.stdout_pipe != nil || process.opts.stdout_pipe != nil
    stderr_pipe_ok := process.stderr_pipe != nil || process.opts.stderr_pipe != nil
    stdin_pipe_ok := process.stdin_pipe != nil || process.opts.stdin_pipe != nil
    MSG :: "the state of `Process` does not match its `opts`"
    switch process.opts.output {
    case .Share, .Silent:
        ok = testing.expect(t, !stdout_pipe_ok && !stderr_pipe_ok, MSG, loc = loc)
    case .Capture:
        ok = testing.expect(t, stdout_pipe_ok && stderr_pipe_ok, MSG, loc = loc)
    case .Capture_Combine, .Capture_Stdout, .Capture_Stderr:
        ok = testing.expect(t, stdout_pipe_ok && !stderr_pipe_ok, MSG, loc = loc)
    }
    switch process.opts.input {
    case .Share, .Nothing:
        ok = testing.expect(t, !stdin_pipe_ok, MSG, loc = loc)
    case .Pipe:
        ok = testing.expect(t, stdin_pipe_ok, MSG, loc = loc)
    }

    return
}

expect_array :: proc(
    t: ^testing.T,
    value, expected: $T/[]$E,
    loc := #caller_location,
) -> (
    ok: bool,
) where intrinsics.type_is_comparable(E) {
    return testing.expectf(
        t,
        slice.equal(value, expected),
        "expected %v (%v), got %v (%v)",
        expected,
        len(expected),
        value,
        len(value),
        loc = loc,
    )
}

