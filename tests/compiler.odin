package tests

import lib ".."
import "core:os"
import "core:testing"

REPO_ROOT :: #config(REPO_ROOT, "")
RATS_DIR :: REPO_ROOT + "/" + ODIN_BUILD_PROJECT_NAME + "/rats/compiler"

@(test)
compiler :: proc(t: ^testing.T) {
    cc, cc_ok := lib.unwrap(lib.command_make("gcc"))
    if !cc_ok {return}
    defer lib.command_destroy(&cc)
    cc.opts.output = .Capture
    lib.command_append_many(&cc, "-o", RATS_DIR + EXEC_PATH, RATS_DIR + "/main.c")

    EXEC_PATH :: "/main.exe" when ODIN_OS in lib.WINDOWS_OS else "/main"

    result, result_ok := lib.unwrap(lib.command_run(cc))
    if !result_ok {return}
    defer lib.result_destroy(&result)
    if !expect_result(t, result) {return}

    compiled_prog := lib.program(RATS_DIR + EXEC_PATH, context.temp_allocator)
    if !testing.expect(t, compiled_prog.found, "The rat program is not found") {return}
    result2, result2_ok := lib.unwrap(lib.program_run(compiled_prog, {}, {output = .Capture}))
    if !result2_ok {return}
    defer lib.result_destroy(&result2)
    if !expect_result(t, result2, "Hello, World!\n", "") {return}

    if os.exists(RATS_DIR + EXEC_PATH) {
        os.remove(RATS_DIR + EXEC_PATH)
    }
}

