package tests

import lib ".."
import "core:os"
import "core:testing"

@(test)
hello :: proc(t: ^testing.T) {
    lib.enable_default_flags({.Use_Context_Logger})

    ok: bool
    sh := lib.program("sh")

    result: lib.Process_Result
    result, ok = lib.run_prog_sync(sh, {"-c", "echo 'Hello, World!'"}, .Share)
    if !ok {
        testing.fail(t)
    } else {
        assert(result.exit == nil && len(result.stdout) == 0 && len(result.stderr) == 0)
    }
    lib.process_result_destroy(&result)

    result, ok = lib.run_prog_sync(sh, {"-c", "echo 'Hello, World!'"}, .Capture)
    if !ok {
        testing.fail(t)
    } else {
        assert(result.exit == nil && len(result.stderr) == 0)
    }
    if !testing.expect_value(t, result.stdout, "Hello, World!\n") {
        testing.fail(t)
    }
    lib.process_result_destroy(&result)

    result, ok = lib.run_prog_sync(sh, {"-c", "echo 'Hello, World!'"}, .Silent)
    if !ok {
        testing.fail(t)
    } else {
        assert(result.exit == nil && len(result.stdout) == 0 && len(result.stderr) == 0)
    }
    lib.process_result_destroy(&result)
}

