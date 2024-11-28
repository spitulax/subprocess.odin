package tests

import lib ".."
import "core:testing"

@(test)
capture :: proc(t: ^testing.T) {
    lib.enable_default_flags({.Use_Context_Logger, .Echo_Commands})
    sh := lib.program("sh")

    result1, result1_ok := lib.unwrap(
        lib.run_prog_sync(sh, {"-c", "echo 'HELLO, STDOUT!' > /dev/stdout"}, .Capture),
    )
    defer lib.process_result_destroy(&result1)
    if result1_ok {
        testing.expect_value(t, result1.exit, nil)
        testing.expect_value(t, result1.stdout, "HELLO, STDOUT!\n")
        testing.expect_value(t, result1.stderr, "")
    }

    result2, result2_ok := lib.unwrap(
        lib.run_prog_sync(sh, {"-c", "echo 'HELLO, STDERR!' > /dev/stderr"}, .Capture),
    )
    defer lib.process_result_destroy(&result2)
    if result2_ok {
        testing.expect_value(t, result1.exit, nil)
        testing.expect_value(t, result2.stdout, "")
        testing.expect_value(t, result2.stderr, "HELLO, STDERR!\n")
    }

    result3, result3_ok := lib.unwrap(
        lib.run_prog_sync(
            sh,
            {"-c", "echo 'HELLO, STDOUT!' > /dev/stdout; echo 'HELLO, STDERR!' > /dev/stderr"},
            .Capture,
        ),
    )
    defer lib.process_result_destroy(&result3)
    if result3_ok {
        testing.expect_value(t, result1.exit, nil)
        testing.expect_value(t, result3.stdout, "HELLO, STDOUT!\n")
        testing.expect_value(t, result3.stderr, "HELLO, STDERR!\n")
    }
}

