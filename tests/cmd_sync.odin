package tests

import lib ".."
import "core:log"
import "core:testing"
import "core:time"

@(test)
cmd_sync :: proc(t: ^testing.T) {
    before := time.now()
    results: [10]lib.Result
    defer lib.result_destroy_many(results[:])
    for &result in results {
        ok: bool
        result, ok = lib.unwrap(lib.run_shell("echo HELLO, WORLD!", {output = .Capture}))
        if ok {
            expect_result(t, result, "HELLO, WORLD!" + NL, "")
        }
    }
    log.infof("Time elapsed: %v", time.since(before))
}

