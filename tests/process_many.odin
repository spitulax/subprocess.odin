package tests

import lib ".."
import "core:log"
import "core:testing"

create_processes :: proc() -> (processes: [10]lib.Process, ok: bool) {
    for &process in processes {
        process = lib.unwrap(
            lib.run_shell_async("echo HELLO, WORLD!", {output = .Capture}),
        ) or_return
    }
    return processes, true
}

@(test)
process_many :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    {
        processes, processes_ok := create_processes()
        if !processes_ok {return}
        results := lib.unwrap(lib.process_wait_many(processes[:]))
        defer lib.result_destroy_many(results)
        for result, i in results {
            expect_success(t, result)
            testing.expect_value(t, processes[i].alive, false)
            testing.expect_value(t, result.stdout, "HELLO, WORLD!" + NL)
            testing.expect_value(t, result.stderr, "")
        }
    }

    {
        processes, processes_ok := create_processes()
        if !processes_ok {return}
        result_errs := lib.process_wait_many(processes[:])
        defer lib.result_destroy_many(&result_errs)
        for result, i in result_errs {
            if result.err != nil {
                log.error(result.err)
            } else {
                expect_success(t, result.result)
                testing.expect_value(t, processes[i].alive, false)
                testing.expect_value(t, result.result.stdout, "HELLO, WORLD!" + NL)
                testing.expect_value(t, result.result.stderr, "")
            }
        }
    }
}

