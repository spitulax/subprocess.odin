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
        results: [3]lib.Process_Result
        oks: [3]bool
        results[0], oks[0] = lib.unwrap(lib.command_run_sync(cmd, .Share))
        results[1], oks[1] = lib.unwrap(lib.command_run_sync(cmd, .Capture))
        results[2], oks[2] = lib.unwrap(lib.command_run_sync(cmd, .Silent))
        defer lib.process_result_destroy_many(results[:])
        for &x, i in results {
            if !oks[i] {
                continue
            }
            expect_success(t, x)
            testing.expect_value(t, x.stdout, "Hello, World!" + NL if i == 1 else "")
            testing.expect_value(t, x.stderr, "")
        }
    }

    {
        PROCESSES :: 5
        processes: [PROCESSES]lib.Process
        for i in 0 ..< PROCESSES {
            processes[i] = lib.unwrap(lib.command_run_async(cmd, .Capture))
        }
        res := lib.process_wait_many(processes[:])
        defer {
            proc_res, _ := soa_unzip(res)
            lib.process_result_destroy_many(proc_res)
        }
        defer delete(res)
        testing.expect_value(t, len(res), PROCESSES)
        for x in res {
            if x.err != nil {
                log.error(x.err)
            } else {
                expect_success(t, x.result)
                testing.expect_value(t, x.result.stdout, "Hello, World!" + NL)
                testing.expect_value(t, x.result.stderr, "")
            }
        }
    }
}

