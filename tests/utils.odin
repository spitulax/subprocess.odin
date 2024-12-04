package tests

import lib ".."
import "base:runtime"
import "core:fmt"
import "core:testing"


when ODIN_OS in lib.POSIX_OS {
    NL :: "\n"
    SH :: "sh"
    CMD :: "-c" // shell flag to execute the next argument as a command
} else when ODIN_OS in lib.WINDOWS_OS {
    NL :: "\r\n"
    SH :: "cmd"
    CMD :: "/C"
}

expect_success :: proc(t: ^testing.T, result: lib.Process_Result) -> bool {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    return testing.expect(
        t,
        lib.process_result_success(result),
        fmt.tprintf("Exited with code %v", result.exit),
    )
}
