package tests

import lib ".."
import "core:testing"

@(test)
capture :: proc(t: ^testing.T) {
    {
        opts := lib.Exec_Opts {
            output = .Capture,
        }
        result1, result1_ok := lib.unwrap(lib.run_shell("echo HELLO, STDOUT!", opts))
        defer lib.result_destroy(&result1)
        if result1_ok {
            expect_result(t, result1, "HELLO, STDOUT!" + NL, "")
        }

        result2, result2_ok := lib.unwrap(lib.run_shell("echo HELLO, STDERR!>&2", opts))
        defer lib.result_destroy(&result2)
        if result2_ok {
            expect_result(t, result2, "", "HELLO, STDERR!" + NL)
        }

        result3, result3_ok := lib.unwrap(
            lib.run_shell("echo HELLO, STDOUT!&&echo HELLO, STDERR!>&2", opts),
        )
        defer lib.result_destroy(&result3)
        if result3_ok {
            expect_result(t, result3, "HELLO, STDOUT!" + NL, "HELLO, STDERR!" + NL)
        }
    }

    {
        opts := lib.Exec_Opts {
            output = .Capture_Combine,
        }
        result1, result1_ok := lib.unwrap(lib.run_shell("echo HELLO, STDOUT!", opts))
        defer lib.result_destroy(&result1)
        if result1_ok {
            expect_result(t, result1, "HELLO, STDOUT!" + NL, "")
        }

        result2, result2_ok := lib.unwrap(lib.run_shell("echo HELLO, STDERR!>&2", opts))
        defer lib.result_destroy(&result2)
        if result2_ok {
            expect_result(t, result2, "HELLO, STDERR!" + NL, "")
        }

        result3, result3_ok := lib.unwrap(
            lib.run_shell("echo HELLO, STDOUT!&&echo HELLO, STDERR!>&2", opts),
        )
        defer lib.result_destroy(&result3)
        if result3_ok {
            expect_result(t, result3, "HELLO, STDOUT!" + NL + "HELLO, STDERR!" + NL, "")
        }
    }
}

