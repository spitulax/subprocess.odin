package tests

import lib ".."
import "core:testing"

@(test)
program :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    _, err := lib.program_run(
        lib.program("notarealcommand", context.temp_allocator),
        {"--help"},
        alloc = context.temp_allocator,
    )
    testing.expect_value(t, err, lib.General_Error.Program_Not_Found)
}

