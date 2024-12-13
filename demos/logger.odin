package demos

import sp ".."
import "core:log"

main :: proc() {
    // No allocations
    context.logger = sp.create_logger()

    sp.log_info("Hello!")
    // Now it's the same as
    log.info("Hello!")

    log.debug("Hello debug!")
    log.info("Hello info!")
    log.warn("Hello warn!")
    log.error("Hello error!")
    log.fatal("Hello fatal!")
}

