package tests

import lib ".."
import "core:testing"

@(test)
escaping :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    bash := lib.program("bash")
    if !testing.expect(t, bash.found, "Bash not found") {return}

    {
        result, ok := lib.unwrap(lib.run_shell_sync("echo \"Hello, World!\"", .Capture))
        defer lib.process_result_destroy(&result)
        when ODIN_OS in lib.POSIX_OS {
            testing.expect_value(t, result.stdout, "Hello, World!" + NL)
        } else when ODIN_OS in lib.WINDOWS_OS {
            testing.expect_value(t, result.stdout, "\"Hello, World!\"" + NL)
        }
    }

    {
        result, ok := lib.unwrap(lib.run_prog_sync(bash, {"-c", "echo \"~\""}, .Capture))
        defer lib.process_result_destroy(&result)
        testing.expect_value(t, result.stdout, "~\n")
    }
}
