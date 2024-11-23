package tests

import lib ".."
import "core:log"
import "core:testing"

wrap_error :: proc(t: ^testing.T, err: lib.Error) {
    if err != nil {
        log.errorf(lib.strerror(err, context.temp_allocator))
        testing.fail(t)
    }
}

