package tests

import lib ".."
import "core:testing"

// NOTE: This will get called first because tests are sorted alphabetically.
// Just don't forget to include `tests._init` in `ODIN_TEST_NAMES`.
@(test)
_init :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})
}

