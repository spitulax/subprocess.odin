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

    cc, cc_ok := lib.unwrap(lib.command_make("gcc"))
    if !cc_ok {return}
    defer lib.command_destroy(&cc)
    cc.opts.output = .Capture
    cc.opts.inherit_env = true
    lib.command_append_many(&cc, "-o", RATS_DIR + EXEC_PATH, RATS_DIR + "/main.c")

    EXEC_PATH :: "/main.exe" when ODIN_OS in lib.WINDOWS_OS else "/main"

    result, result_ok := lib.unwrap(lib.command_run(cc))
    defer lib.result_destroy(&result)
    if result_ok {
        if !lib.result_success(result) {
            log.errorf("gcc exited with %v: %s", result.exit, result.stderr)
            return
        }
    }

    compiled_prog := lib.program(RATS_DIR + EXEC_PATH, context.temp_allocator)
    if !testing.expect(t, compiled_prog.found) {return}
    result2, result2_ok := lib.unwrap(lib.program_run(compiled_prog, {}, {output = .Capture, inherit_env = true}))
    defer lib.result_destroy(&result2)
    if result2_ok {
        if !lib.result_success(result2) {
            log.errorf("program exited with %v: %s", result2.exit, result2.stderr)
            return
        }
        testing.expect_value(t, result2.stdout, "Hello, World!\n")
        testing.expect_value(t, result2.stderr, "")
    }

    if os.exists(RATS_DIR + EXEC_PATH) {
        os.remove(RATS_DIR + EXEC_PATH)
    }
}

