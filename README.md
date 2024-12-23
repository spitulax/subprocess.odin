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
    cmd, cmd_err := sp.command_make("cc") // Will search from PATH
    // File paths are also valid
    // prog := sp.command_make("./bin/cc")
    if cmd_err != nil {return}
    defer sp.command_destroy(&cmd)
    sp.command_append(&cmd, "--version")
    result, result_err := sp.command_run(cmd)
    if result_err == nil {
        sp.log_info(result)
        sp.log_info("Output:", string(result.stdout))
    }
}

// See more examples in demos/examples.odin
```
