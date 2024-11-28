package tests

import lib ".."
import "core:log"
import "core:testing"
import "core:time"

@(test)
cmd_async :: proc(t: ^testing.T) {
    lib.enable_default_flags({.Use_Context_Logger, .Echo_Commands})

    before := time.now()
    processes: [10]lib.Process
    sh := lib.program("sh")
    for &process in processes {
        process = lib.unwrap(lib.run_prog_async(sh, {"-c", "echo 'HELLO, WORLD!'"}, .Capture))
    }
    results := lib.process_wait_many(processes[:], context.temp_allocator)
    for result in results {
        if result.err != nil {
            log.error(result.err)
        } else {
            testing.expect_value(t, result.result.exit, nil)
            testing.expect_value(t, result.result.stdout, "HELLO, WORLD!\n")
            testing.expect_value(t, result.result.stderr, "")
        }
    }
    log.infof("Time elapsed: %v", time.since(before))
}

