package demos

import sp ".."

main :: proc() {
    sp.default_flags_enable({.Echo_Commands_Debug})

    result, ok := sp.unwrap(sp.run_shell("echo Hello, World!", {output = .Capture}))
    defer sp.result_destroy(&result)
    if ok {
        sp.log_info(result)
        sp.log_info("Output:", string(result.stdout))
    }
}

