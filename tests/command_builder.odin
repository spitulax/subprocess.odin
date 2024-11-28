package tests

import lib ".."
import "core:log"
import "core:testing"

@(test)
command_builder :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    cmd := lib.unwrap(lib.command_make("sh"))
    defer lib.command_destroy(&cmd)
    lib.command_append(&cmd, "-c")
    lib.command_append(&cmd, "echo 'Hello, World!'")

    {
        defer lib.command_destroy_results(&cmd)
        results: [3]^lib.Process_Result
        oks: [3]bool
        results[0], oks[0] = lib.unwrap(lib.command_run_sync(&cmd, .Share))
        results[1], oks[1] = lib.unwrap(lib.command_run_sync(&cmd, .Capture))
        results[2], oks[2] = lib.unwrap(lib.command_run_sync(&cmd, .Silent))
        testing.expect_value(t, len(cmd.results), 3)
        for &x, i in cmd.results {
            testing.expect_value(t, &x, results[i])
            if !oks[i] {
                continue
            }
            testing.expect_value(t, x.exit, nil)
            testing.expect_value(t, x.stdout, "Hello, World!\n" if i == 1 else "")
            testing.expect_value(t, x.stderr, "")
        }
    }

    {
        defer lib.command_destroy_results(&cmd)
        PROCESSES :: 5
        processes: [PROCESSES]^lib.Process
        for i in 0 ..< PROCESSES {
            processes[i] = lib.unwrap(lib.command_run_async(&cmd, .Capture))
            testing.expect_value(t, processes[i], &cmd.running_processes[i])
        }
        testing.expect_value(t, len(cmd.running_processes), PROCESSES)
        res := lib.command_wait_all(&cmd)
        defer delete(res)
        testing.expect_value(t, len(cmd.running_processes), 0)
        testing.expect_value(t, len(cmd.results), PROCESSES)
        for &x, i in res {
            testing.expect_value(t, x.result, &cmd.results[i])
            if x.err != nil {
                log.error(x.err)
            } else {
                testing.expect_value(t, x.result.exit, nil)
                testing.expect_value(t, x.result.stdout, "Hello, World!\n")
                testing.expect_value(t, x.result.stderr, "")
            }
        }
    }
}

