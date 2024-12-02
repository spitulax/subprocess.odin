package tests

import lib ".."
import "core:testing"

@(test)
hello :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})
    sh := lib.program(SH)

    ok: bool
    result: lib.Process_Result
    result, ok = lib.unwrap(lib.run_prog_sync(sh, {CMD, "echo Hello, World!"}, .Share))
    if ok {
        expect_success(t, result)
        testing.expect_value(t, result.stdout, "")
        testing.expect_value(t, result.stderr, "")
    }
    lib.process_result_destroy(&result)

    result, ok = lib.unwrap(lib.run_prog_sync(sh, {CMD, "echo Hello, World!"}, .Capture))
    if ok {
        expect_success(t, result)
        testing.expect_value(t, result.stdout, "Hello, World!" + NL)
        testing.expect_value(t, result.stderr, "")
    }
    lib.process_result_destroy(&result)

    result, ok = lib.unwrap(lib.run_prog_sync(sh, {CMD, "echo Hello, World!"}, .Silent))
    if ok {
        expect_success(t, result)
        testing.expect_value(t, result.stdout, "")
        testing.expect_value(t, result.stderr, "")
    }
    lib.process_result_destroy(&result)
}

