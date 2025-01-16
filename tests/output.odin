package tests

import lib ".."
import "base:runtime"
import "core:testing"

@(private = "file")
STDOUT :: "HELLO, STDOUT!" + NL
@(private = "file")
STDERR :: "HELLO, STDERR!" + NL

@(private = "file")
CMD_STDOUT :: "echo HELLO, STDOUT!"
@(private = "file")
CMD_STDERR :: "echo HELLO, STDERR!>&2"
@(private = "file")
CMD_BOTH :: "echo HELLO, STDOUT!&&echo HELLO, STDERR!>&2"

@(private = "file")
test :: proc(
    t: ^testing.T,
    expected_stdout: [3]string,
    expected_stderr: [3]string,
    opt: lib.Output_Option,
) -> (
    ok: bool,
) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    opts := lib.Exec_Opts {
        output = opt,
    }
    r0 := lib.unwrap(lib.run_shell(CMD_STDOUT, opts, context.temp_allocator)) or_return
    expect_result(t, r0, expected_stdout[0], expected_stderr[0])
    r1 := lib.unwrap(lib.run_shell(CMD_STDERR, opts, context.temp_allocator)) or_return
    expect_result(t, r1, expected_stdout[1], expected_stderr[1])
    r2 := lib.unwrap(lib.run_shell(CMD_BOTH, opts, context.temp_allocator)) or_return
    expect_result(t, r2, expected_stdout[2], expected_stderr[2])
    return true
}

@(private = "file")
start :: proc(t: ^testing.T) -> (ok: bool) {
    opt: lib.Output_Option
    switch opt {
    case .Silent:
    case .Share:
    case .Capture:
    case .Capture_Combine:
    case .Capture_Stdout:
    case .Capture_Stderr:
    }

    test(t, {"", "", ""}, {"", "", ""}, .Share) or_return
    test(t, {"", "", ""}, {"", "", ""}, .Silent) or_return
    test(t, {STDOUT, "", STDOUT}, {"", STDERR, STDERR}, .Capture) or_return
    test(t, {STDOUT, STDERR, STDOUT + STDERR}, {"", "", ""}, .Capture_Combine) or_return
    test(t, {STDOUT, "", STDOUT}, {"", "", ""}, .Capture_Stdout) or_return
    test(t, {"", STDERR, STDERR}, {"", "", ""}, .Capture_Stderr) or_return

    return true
}

@(test)
output :: proc(t: ^testing.T) {
    start(t)
}

