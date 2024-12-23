package tests

import lib ".."
import "core:log"
import "core:testing"
import "core:time"

@(test)
cmd_async :: proc(t: ^testing.T) {
    before := time.now()
    processes: [10]lib.Process
    for &process in processes {
        ok: bool
        process, ok = lib.unwrap(lib.run_shell_async("echo HELLO, WORLD!", {output = .Capture}))
        if !ok || !expect_process(t, process) {return}
    }
    results := lib.unwrap(
        lib.process_wait_many(processes[:], context.temp_allocator),
        alloc = context.temp_allocator,
    )
    for result, i in results {
        testing.expect_value(t, processes[i].alive, false)
        expect_result(t, result, "HELLO, WORLD!" + NL, "")
    }
    log.infof("Time elapsed: %v", time.since(before))
}

