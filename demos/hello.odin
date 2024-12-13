package demos

import sp ".."

main :: proc() {
    sp.default_flags_enable({.Echo_Commands_Debug})

    result, ok := sp.unwrap(sp.run_shell_sync("echo Hello, World!", .Capture))
    defer sp.process_result_destroy(&result)
    if ok {
        sp.log_info(result)
    }
}

