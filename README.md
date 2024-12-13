<h1 align="center">subprocess.odin</h1>
<p align="center">An Odin library for spawning child processes.</p>

## Features

- Cross-platform (POSIX and Windows)
- Capturing output
- Sending input
- Asynchronous/parallel execution
- Command builder
- Checking if program exists
- Running shell commands (System-specific shell)
- Passing environment variables to process

## Usage

- Clone the repo to your project
- Import the package into your Odin file

## Examples

See [`demos/examples.odin`](./demos/examples.odin).

```odin
package main

import sp "subprocess.odin"

main :: proc() {
    prog := sp.program("cc") // Will search from PATH
    // File path is also valid
    // prog := sp.program("./bin/cc")
    if !prog.found {return}
    result, err := sp.run_prog_sync(prog, {"--version"})
    defer sp.process_result_destroy(&result)
    if err == nil {
        sp.log_info(result)
    }
}

// See more examples in demos/examples.odin
```
