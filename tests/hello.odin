package tests

import lib ".."
import "core:testing"

@(test)
hello :: proc(t: ^testing.T) {
    lib.enable_default_flags({.Use_Context_Logger, .Echo_Commands})

    err: lib.Error
    sh := lib.program("sh")

    result: lib.Process_Result
    result, err = lib.run_prog_sync(sh, {"-c", "echo 'Hello, World!'"}, .Share)
    wrap(t, err)
    if err == nil {
        assert(result.exit == nil && len(result.stdout) == 0 && len(result.stderr) == 0)
    }
    lib.process_result_destroy(&result)

    result, err = lib.run_prog_sync(sh, {"-c", "echo 'Hello, World!'"}, .Capture)
    wrap(t, err)
    if err == nil {
        assert(result.exit == nil && len(result.stderr) == 0)
    }
    testing.expect_value(t, result.stdout, "Hello, World!\n")
    lib.process_result_destroy(&result)

    result, err = lib.run_prog_sync(sh, {"-c", "echo 'Hello, World!'"}, .Silent)
    wrap(t, err)
    if err == nil {
        assert(result.exit == nil && len(result.stdout) == 0 && len(result.stderr) == 0)
    }
    lib.process_result_destroy(&result)
}

