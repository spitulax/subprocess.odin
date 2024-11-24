package hello

import lib ".."

main :: proc() {
    lib.process_tracker_init()
    defer lib.process_tracker_destroy()

    lib.enable_default_flags({.Echo_Commands_Debug})

    when ODIN_OS in lib.POSIX_OS {
        sh := lib.program("sh")

        result, err := lib.run_prog_sync(sh, {"-c", "echo 'Hello, World!'"}, .Capture)
        if err != nil {
            lib.log_error(lib.error_str(err))
        }
        defer lib.process_result_destroy(&result)
        lib.log_info(result)
    } else {
        unimplemented()
    }
}

