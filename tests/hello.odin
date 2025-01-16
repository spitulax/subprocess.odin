package tests

// I really don't know what is this for since the cases are already covered by `output` anyway
// But I don't want to remove it

import lib ".."
import "core:testing"

@(test)
hello :: proc(t: ^testing.T) {
    ok: bool
    result: lib.Result
    result, ok = lib.unwrap(lib.run_shell_sync("echo Hello, World!"))
    if ok {
        expect_result(t, result, "", "")
    }
    lib.result_destroy(&result)

    result, ok = lib.unwrap(lib.run_shell_sync("echo Hello, World!", {output = .Capture}))
    if ok {
        expect_result(t, result, "Hello, World!" + NL, "")
    }
    lib.result_destroy(&result)

    result, ok = lib.unwrap(lib.run_shell_sync("echo Hello, World!", {output = .Silent}))
    if ok {
        expect_result(t, result, "", "")
    }
    lib.result_destroy(&result)
}

