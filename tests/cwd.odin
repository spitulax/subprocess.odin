package tests

import lib ".."
import fp "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
cwd :: proc(t: ^testing.T) {
    when ODIN_OS in lib.POSIX_OS {
        COMMAND :: "echo $PWD"
    } else when ODIN_OS in lib.WINDOWS_OS {
        COMMAND :: "cd"
    }

    path := fp.join({REPO_ROOT, "tests"}, context.temp_allocator)
    result, result_ok := lib.unwrap(lib.run_shell(COMMAND, {output = .Capture, cwd = path}))
    if !result_ok {return}
    defer lib.result_destroy(&result)
    if !expect_result(
        t,
        result,
        strings.concatenate({path, NL}, context.temp_allocator),
        "",
    ) {return}
}

