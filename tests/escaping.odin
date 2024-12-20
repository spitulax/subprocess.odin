package tests

import lib ".."
import "core:testing"

@(test)
escaping :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    bash, bash_ok := lib.unwrap(lib.command_make("bash"))
    if !bash_ok {return}
    defer lib.command_destroy(&bash)

    {
        result := lib.unwrap(lib.run_shell_sync("echo \"Hello, World!\"", {output = .Capture}))
        defer lib.result_destroy(&result)
        when ODIN_OS in lib.POSIX_OS {
            testing.expect_value(t, result.stdout, "Hello, World!" + NL)
        } else when ODIN_OS in lib.WINDOWS_OS {
            testing.expect_value(t, result.stdout, "\"Hello, World!\"" + NL)
        }
    }

    {
        result := lib.unwrap(
            lib.command_run(bash, lib.Exec_Opts{output = .Capture}, {"-c", "echo \"~\""}),
        )
        defer lib.result_destroy(&result)
        testing.expect_value(t, result.stdout, "~\n")
    }
}

