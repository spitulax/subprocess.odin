package tests

import lib ".."
import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:testing"


when ODIN_OS in lib.POSIX_OS {
    NL :: "\n"
    SH :: "sh"
    CMD :: "-c" // shell flag to execute the next argument as a command
} else when ODIN_OS in lib.WINDOWS_OS {
    NL :: "\r\n"
    SH :: "cmd.exe"
    CMD :: "/C"
}

trim_nl :: proc(s: string) -> string {
    return strings.trim_suffix(s, NL)
}

expect_success :: proc(t: ^testing.T, result: lib.Result, loc := #caller_location) -> bool {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    return testing.expect(
        t,
        lib.result_success(result),
        fmt.tprintf("Exited with code %v", result.exit),
        loc = loc,
    )
}

