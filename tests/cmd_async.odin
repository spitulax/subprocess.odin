package tests

import lib ".."
import "core:log"
import "core:testing"
import "core:time"

@(test)
cmd_async :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})
    sh := lib.program(SH)

    before := time.now()
    processes: [10]lib.Process
    for &process in processes {
        // MAYBE: store the location of where `run_prog*` is called in `Process`
        // then store it and the location of `process_wait*` in `Process_Result`
        process = lib.unwrap(lib.run_prog_async(sh, {CMD, "echo HELLO, WORLD!"}, .Capture))
    }
    results := lib.process_wait_many(processes[:], context.temp_allocator)
    for result in results {
        if result.err != nil {
            log.error(result.err)
        } else {
            expect_success(t, result.result)
            testing.expect_value(t, result.result.stdout, "HELLO, WORLD!" + NL)
            testing.expect_value(t, result.result.stderr, "")
        }
    }
    log.infof("Time elapsed: %v", time.since(before))
}

