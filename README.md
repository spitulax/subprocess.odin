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

import sp "subprocess"

main :: proc() {
    cmd, _ := sp.command_make("cc") // Will search from PATH
    // File paths are also valid
    // prog, _ := sp.command_make("./bin/cc")
    defer sp.command_destroy(&cmd)
    sp.command_append(&cmd, "--version")
    result, _ := sp.command_run(cmd, sp.Exec_Opts{output = .Capture})
    defer sp.result_destroy(&result)
    sp.log_info("Output:", string(result.stdout))
}

// See more examples in demos/examples.odin
// Tests are also great examples
```

## Building Docs

> [!WARNING]
> The generated documentation is not great. I advise you to look at the source code for
> documentation.

1. Compile `odin-doc`
   1. Clone <https://github.com/odin-lang/pkg.odin-lang.org>
   2. Build it: `odin build . -out:odin-doc`

Then,

2. `make docs`
3. `cd docs/site`
4. `python3 -m http.server 10101`
5. Go to `localhost:10101`

Or alternatively,

2. `cd docs`
3. `make serve`
4. Go to `localhost:10101`

## Changelog

See [changelog](CHANGELOG.md).
