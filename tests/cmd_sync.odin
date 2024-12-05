package tests

import lib ".."
import "core:log"
import "core:testing"
import "core:time"

@(test)
cmd_sync :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    before := time.now()
    results: [10]lib.Process_Result
    defer lib.process_result_destroy_many(results[:])
    for &result in results {
        ok: bool
        result, ok = lib.unwrap(lib.run_shell_sync("echo HELLO, WORLD!", .Capture))
        if ok {
            expect_success(t, result)
            testing.expect_value(t, result.stdout, "HELLO, WORLD!" + NL)
            testing.expect_value(t, result.stderr, "")
        }
    }
    log.infof("Time elapsed: %v", time.since(before))
}

