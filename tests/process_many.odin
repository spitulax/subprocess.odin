package tests

import lib ".."
import "core:log"
import "core:testing"

@(private = "file")
create_processes :: proc(
    t: ^testing.T,
    loc := #caller_location,
) -> (
    processes: [10]lib.Process,
    ok: bool,
) {
    for &process in processes {
        process, ok = lib.unwrap(lib.run_shell_async("echo HELLO, WORLD!", {output = .Capture}))
        if !ok || !expect_process(t, process, loc) {return}
    }
    return processes, true
}

@(test)
process_many :: proc(t: ^testing.T) {
    {
        processes, processes_ok := create_processes(t)
        if !processes_ok {return}
        results, results_ok := lib.unwrap(lib.process_wait_many(processes[:]))
        if !results_ok {return}
        defer lib.result_destroy_many(results)
        for result, i in results {
            testing.expect_value(t, processes[i].alive, false)
            expect_result(t, result, "HELLO, WORLD!" + NL, "")
        }
    }

    {
        processes, processes_ok := create_processes(t)
        if !processes_ok {return}
        result_errs := lib.process_wait_many(processes[:])
        defer lib.result_destroy_many(&result_errs)
        for result, i in result_errs {
            if result.err != nil {
                log.error(result.err)
            } else {
                testing.expect_value(t, processes[i].alive, false)
                expect_result(t, result.result, "HELLO, WORLD!" + NL, "")
            }
        }
    }
}

