package tests

import lib ".."
import "core:log"
import "core:testing"

@(test)
command_builder :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    cmd := lib.unwrap(lib.command_make(SH))
    defer lib.command_destroy(&cmd)
    if !testing.expect(t, cmd.prog.found) {return}
    lib.command_append(&cmd, CMD)
    lib.command_append(&cmd, "echo Hello, World!")

    {
        results: [3]lib.Result
        oks: [3]bool
        results[0], oks[0] = lib.unwrap(lib.command_run(cmd))
        results[1], oks[1] = lib.unwrap(lib.command_run(cmd, lib.Exec_Opts{output = .Capture}))
        results[2], oks[2] = lib.unwrap(lib.command_run(cmd, lib.Exec_Opts{output = .Silent}))
        defer lib.result_destroy_many(results[:])
        for &x, i in results {
            if !oks[i] {
                continue
            }
            expect_result(t, x, "Hello, World!" + NL if i == 1 else "", "")
        }
    }

    {
        PROCESSES :: 5
        processes: [PROCESSES]lib.Process
        for &process in processes {
            ok: bool
            process, ok = lib.unwrap(lib.command_run_async(cmd, lib.Exec_Opts{output = .Capture}))
            if !ok {return}
        }
        res, res_ok := lib.unwrap(lib.process_wait_many(processes[:]))
        defer lib.result_destroy_many(res)
        if !res_ok {return}
        testing.expect_value(t, len(res), PROCESSES)
        for x in res {
            expect_result(t, x, "Hello, World!" + NL, "")
        }
    }
}

