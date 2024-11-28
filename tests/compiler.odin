package tests

import lib ".."
import "core:log"
import "core:os"
import "core:testing"

REPO_ROOT :: #config(REPO_ROOT, "")
RATS_DIR :: REPO_ROOT + "/" + ODIN_BUILD_PROJECT_NAME + "/rats/compiler"

@(test)
compiler :: proc(t: ^testing.T) {
    lib.enable_default_flags({.Use_Context_Logger, .Echo_Commands})

    sh := lib.program("sh")
    cc := lib.program("cc")

    result, result_ok := lib.unwrap(
        lib.run_prog_sync(cc, {"-o", RATS_DIR + "/main", RATS_DIR + "/main.c"}, .Capture),
    )
    defer lib.process_result_destroy(&result)
    if result_ok {
        if result.exit != nil {
            log.errorf("%s exited with %v: %s", cc.name, result.exit, result.stderr)
            return
        }
    }

    // TODO: specify environment variable
    // eg. adding ./rats/gcc/main to PATH for this operation to call it without sh
    result2, result2_ok := lib.unwrap(lib.run_prog_sync(sh, {"-c", RATS_DIR + "/main"}, .Capture))
    defer lib.process_result_destroy(&result2)
    if result2_ok {
        if result2.exit != nil {
            log.errorf("shell exited with %v: %s", result2.exit, result2.stderr)
            return
        }
        testing.expect_value(t, result2.stdout, "Hello, World!\n")
        testing.expect_value(t, result2.stderr, "")
    }

    if os.exists(RATS_DIR + "/main") {
        os.remove(RATS_DIR + "/main")
    }
}

