package logger

import lib ".."
import "core:log"

main :: proc() {
    // No allocations
    context.logger = lib.create_logger()

    lib.log_info("Hello!")
    // Now it's the same as
    log.info("Hello!")

    log.debug("Hello debug!")
    log.info("Hello info!")
    log.warn("Hello warn!")
    log.error("Hello error!")
    log.fatal("Hello fatal!")
}

