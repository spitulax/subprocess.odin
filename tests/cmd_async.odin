package tests

import lib ".."
import "core:log"
import "core:testing"
import "core:time"

@(test)
cmd_async :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    before := time.now()
    processes: [10]lib.Process
    for &process in processes {
        process = lib.unwrap(lib.run_shell_async("echo HELLO, WORLD!", .Capture))
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

