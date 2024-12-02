package demos

import lib ".."

when ODIN_OS in lib.POSIX_OS {
    SH :: "sh"
    CMD :: "-c" // shell flag to execute the next argument as a command
} else when ODIN_OS in lib.WINDOWS_OS {
    SH :: "cmd"
    CMD :: "/C"
}

main :: proc() {
    lib.default_flags_enable({.Echo_Commands_Debug})

    sh := lib.program(SH)
    result, ok := lib.unwrap(lib.run_prog_sync(sh, {CMD, "echo Hello, World!"}, .Capture))
    defer lib.process_result_destroy(&result)
    if ok {
        lib.log_info(result)
    }
}

