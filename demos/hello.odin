package demos

import lib ".."

main :: proc() {
    lib.default_flags_enable({.Echo_Commands_Debug})

    result, ok := lib.unwrap(lib.run_shell_sync("echo Hello, World!", .Capture))
    defer lib.process_result_destroy(&result)
    if ok {
        lib.log_info(result)
    }
}

