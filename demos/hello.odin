package demos

import lib ".."

main :: proc() {
    lib.enable_default_flags({.Echo_Commands_Debug})

    sh: lib.Program
    when ODIN_OS in lib.POSIX_OS {
        sh = lib.program("sh")

        result, ok := lib.unwrap(lib.run_prog_sync(sh, {"-c", "echo 'Hello, World!'"}, .Capture))
        defer lib.process_result_destroy(&result)
        if ok {
            lib.log_info(result)
        }
    } else {
        unimplemented()
    }
}

