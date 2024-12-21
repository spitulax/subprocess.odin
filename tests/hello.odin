package tests

import lib ".."
import "core:testing"

@(test)
hello :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    ok: bool
    result: lib.Result
    result, ok = lib.unwrap(lib.run_shell_sync("echo Hello, World!"))
    if ok {
        expect_success(t, result)
        testing.expect_value(t, result.stdout, "")
        testing.expect_value(t, result.stderr, "")
    }
    lib.result_destroy(&result)

    result, ok = lib.unwrap(lib.run_shell_sync("echo Hello, World!", {output = .Capture}))
    if ok {
        expect_success(t, result)
        testing.expect_value(t, result.stdout, "Hello, World!" + NL)
        testing.expect_value(t, result.stderr, "")
    }
    lib.result_destroy(&result)

    result, ok = lib.unwrap(lib.run_shell_sync("echo Hello, World!", {output = .Silent}))
    if ok {
        expect_success(t, result)
        testing.expect_value(t, result.stdout, "")
        testing.expect_value(t, result.stderr, "")
    }
    lib.result_destroy(&result)
}

