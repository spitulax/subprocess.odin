package tests

import lib ".."
import "core:testing"

@(test)
capture :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    {
        opts := lib.Exec_Opts {
            output = .Capture,
        }
        result1, result1_ok := lib.unwrap(lib.run_shell("echo HELLO, STDOUT!", opts))
        defer lib.result_destroy(&result1)
        if result1_ok {
            expect_success(t, result1)
            testing.expect_value(t, result1.stdout, "HELLO, STDOUT!" + NL)
            testing.expect_value(t, result1.stderr, "")
        }

        result2, result2_ok := lib.unwrap(lib.run_shell("echo HELLO, STDERR!>&2", opts))
        defer lib.result_destroy(&result2)
        if result2_ok {
            expect_success(t, result2)
            testing.expect_value(t, result2.stdout, "")
            testing.expect_value(t, result2.stderr, "HELLO, STDERR!" + NL)
        }

        result3, result3_ok := lib.unwrap(
            lib.run_shell("echo HELLO, STDOUT!&&echo HELLO, STDERR!>&2", opts),
        )
        defer lib.result_destroy(&result3)
        if result3_ok {
            expect_success(t, result3)
            testing.expect_value(t, result3.stdout, "HELLO, STDOUT!" + NL)
            testing.expect_value(t, result3.stderr, "HELLO, STDERR!" + NL)
        }
    }

    {
        opts := lib.Exec_Opts {
            output = .Capture_Combine,
        }
        result1, result1_ok := lib.unwrap(lib.run_shell("echo HELLO, STDOUT!", opts))
        defer lib.result_destroy(&result1)
        if result1_ok {
            expect_success(t, result1)
            testing.expect_value(t, result1.stdout, "HELLO, STDOUT!" + NL)
            testing.expect_value(t, result1.stderr, "")
        }

        result2, result2_ok := lib.unwrap(lib.run_shell("echo HELLO, STDERR!>&2", opts))
        defer lib.result_destroy(&result2)
        if result2_ok {
            expect_success(t, result2)
            testing.expect_value(t, result2.stdout, "HELLO, STDERR!" + NL)
            testing.expect_value(t, result2.stderr, "")
        }

        result3, result3_ok := lib.unwrap(
            lib.run_shell("echo HELLO, STDOUT!&&echo HELLO, STDERR!>&2", opts),
        )
        defer lib.result_destroy(&result3)
        if result3_ok {
            expect_success(t, result3)
            testing.expect_value(t, result3.stdout, "HELLO, STDOUT!" + NL + "HELLO, STDERR!" + NL)
            testing.expect_value(t, result3.stderr, "")
        }
    }
}

