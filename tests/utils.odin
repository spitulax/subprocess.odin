package tests

import lib ".."
import "core:log"
import "core:testing"

wrap :: proc {
    wrap_error,
    wrap_ok,
}

wrap_error :: proc(t: ^testing.T, err: lib.Error, loc := #caller_location) {
    if err != nil {
        log.errorf(lib.strerror(err, context.temp_allocator), location = loc)
        testing.fail(t, loc)
    }
}

wrap_ok :: proc(t: ^testing.T, ok: bool, loc := #caller_location) {
    if !ok {
        testing.fail(t, loc)
    }
}

