package tests

import lib ".."
import "core:testing"

@(test)
custom_pipes :: proc(t: ^testing.T) {
    cmd, cmd_ok := lib.unwrap(lib.command_make("bash"))
    if !cmd_ok {return}
    defer lib.command_destroy(&cmd)

    {
        lib.command_set(&cmd, "-c", "echo Hello, World!")
        stdout := lib.unwrap(lib.pipe_make())
        defer lib.pipe_destroy(&stdout)
        process := lib.unwrap(
            lib.command_run_async(
                cmd,
                lib.Exec_Opts{output = .Capture_Combine, stdout_pipe = stdout},
            ),
        )
        // NOTE: Deliberate testing. Not destroying the result should be fine because `Capture_Combine`
        // would only allocate buffer for stdout output, but we use our own pipe for stdout so the only
        // thing that would get allocated in fact should not be allocated.
        result := lib.unwrap(lib.process_wait(&process))
        expect_result_bytes(t, result, {}, {}, nil)
        output := lib.unwrap(lib.pipe_read_all(&stdout))
        defer delete(output)
        testing.expect_value(t, string(output), "Hello, World!\n")
    }

    {
        lib.command_set(&cmd, "-c", "echo 'Hello, stdout!' && echo 'Hello, stderr!' >&2")
        stdout := lib.unwrap(lib.pipe_make())
        defer lib.pipe_destroy(&stdout)
        stderr := lib.unwrap(lib.pipe_make())
        defer lib.pipe_destroy(&stderr)
        process := lib.unwrap(
            lib.command_run_async(
                cmd,
                lib.Exec_Opts{output = .Capture, stdout_pipe = stdout, stderr_pipe = stderr},
            ),
        )
        result := lib.unwrap(lib.process_wait(&process))
        expect_result_bytes(t, result, {}, {}, nil)
        stdout_out := lib.unwrap(lib.pipe_read_all(&stdout))
        defer delete(stdout_out)
        stderr_out := lib.unwrap(lib.pipe_read_all(&stderr))
        defer delete(stderr_out)
        testing.expect_value(t, string(stdout_out), "Hello, stdout!\n")
        testing.expect_value(t, string(stderr_out), "Hello, stderr!\n")
    }

    {
        lib.command_set(&cmd, "-c", "read TEST && echo $TEST")
        stdin := lib.unwrap(lib.pipe_make())
        defer lib.pipe_destroy(&stdin)
        process := lib.unwrap(
            lib.command_run_async(
                cmd,
                lib.Exec_Opts{output = .Capture, input = .Pipe, stdin_pipe = stdin},
            ),
        )
        lib.unwrap(lib.pipe_write_string(stdin, "Hello, World!\n", false))
        result := lib.unwrap(lib.process_wait(&process))
        defer lib.result_destroy(&result)
        expect_result(t, result, "Hello, World!\n", "", nil)
    }
}

