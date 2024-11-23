package tests

import lib ".."
import "core:log"
import "core:testing"

@(test)
capture :: proc(t: ^testing.T) {
    lib.enable_default_flags({.Use_Context_Logger, .Echo_Commands})
    sh := lib.program("sh")

    result1, result1_err := lib.run_prog_sync(
        sh,
        {"-c", "echo 'HELLO, STDOUT!' > /dev/stdout"},
        .Capture,
    )
    wrap(t, result1_err)
    defer lib.process_result_destroy(&result1)
    wrap(
        t,
        testing.expect(
            t,
            (result1.stdout == "HELLO, STDOUT!\n" && result1.stderr == ""),
            "Unexpected output",
        ),
    )

    result2, result2_err := lib.run_prog_sync(
        sh,
        {"-c", "echo 'HELLO, STDERR!' > /dev/stderr"},
        .Capture,
    )
    wrap(t, result2_err)
    defer lib.process_result_destroy(&result2)
    wrap(
        t,
        testing.expect(
            t,
            (result2.stderr == "HELLO, STDERR!\n" && result2.stdout == ""),
            "Unexpected output",
        ),
    )

    result3, result3_err := lib.run_prog_sync(
        sh,
        {"-c", "echo 'HELLO, STDOUT!' > /dev/stdout; echo 'HELLO, STDERR!' > /dev/stderr"},
        .Capture,
    )
    wrap(t, result3_err)
    defer lib.process_result_destroy(&result3)
    wrap(
        t,
        testing.expect(
            t,
            (result3.stderr == "HELLO, STDERR!\n" && result3.stdout == "HELLO, STDOUT!\n"),
            "Unexpected output",
        ),
    )
}

