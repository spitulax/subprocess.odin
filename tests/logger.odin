package tests

import lib ".."
import "core:fmt"
import "core:log"
import "core:testing"

main :: proc() {
    // Simple printing
    lib.log_error("Hello, World!")
    lib.log_warn("Hello, World!")
    lib.log_info("Hello, World!")
    lib.log_debug("Hello, World!")

    context.logger = log.create_console_logger()
    defer log.destroy_console_logger(context.logger)
    lib.set_use_context_logger()
    lib.log_error("Hello, World!")
    lib.log_warn("Hello, World!")
    lib.log_info("Hello, World!")
    lib.log_debug("Hello, World!")
}


@(test)
logger :: proc(t: ^testing.T) {
    // Simple printing
    lib.log_error("Hello, World!")
    lib.log_warn("Hello, World!")
    lib.log_info("Hello, World!")
    lib.log_debug("Hello, World!")
}

