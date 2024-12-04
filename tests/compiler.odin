package tests

import lib ".."
import "core:log"
import "core:os"
import "core:testing"

REPO_ROOT :: #config(REPO_ROOT, "")
RATS_DIR :: REPO_ROOT + "/" + ODIN_BUILD_PROJECT_NAME + "/rats/compiler"

@(test)
compiler :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    cc := lib.program("gcc")
    testing.expect(
        t,
        cc.found,
        "GCC was not found. Run this test with GCC available (use mingw in Windows)",
    )

    EXEC_PATH :: "/main.exe" when ODIN_OS in lib.WINDOWS_OS else "/main"

    result, result_ok := lib.unwrap(
        lib.run_prog_sync(cc, {"-o", RATS_DIR + EXEC_PATH, RATS_DIR + "/main.c"}, .Capture),
    )
    defer lib.process_result_destroy(&result)
    if result_ok {
        if !lib.process_result_success(result) {
            log.errorf("%s exited with %v: %s", cc.name, result.exit, result.stderr)
            return
        }
    }

    //compiled_prog := lib.program(RATS_DIR + EXEC_PATH)
    //if !testing.expect(t, compiled_prog.found) {return}
    result2, result2_ok := lib.unwrap(lib.run_prog_sync(RATS_DIR + EXEC_PATH, {}, .Capture))
    defer lib.process_result_destroy(&result2)
    if result2_ok {
        if !lib.process_result_success(result2) {
            log.errorf("shell exited with %v: %s", result2.exit, result2.stderr)
            return
        }
        testing.expect_value(t, result2.stdout, "Hello, World!\n")
        testing.expect_value(t, result2.stderr, "")
    }

    if os.exists(RATS_DIR + EXEC_PATH) {
        os.remove(RATS_DIR + EXEC_PATH)
    }
}

