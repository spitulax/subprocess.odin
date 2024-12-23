package tests

import lib ".."
import "core:testing"

@(private = "file")
run_pipe :: proc(t: ^testing.T, process: ^lib.Process) -> (result: lib.Result, ok: bool) {
    n := lib.unwrap(lib.pipe_write(process.stdin_pipe.?, "Hello", false)) or_return
    testing.expect_value(t, n, 5) or_return
    n = lib.unwrap(lib.pipe_write(process.stdin_pipe.?, " World", true)) or_return
    testing.expect_value(t, n, 6 + len(NL)) or_return
    result = lib.unwrap(lib.process_wait(process)) or_return
    expect_success(t, result) or_return
    return result, true
}

@(private = "file")
run_nothing :: proc(t: ^testing.T, process: ^lib.Process) -> (ok: bool) {
    result := lib.unwrap(lib.process_wait(process)) or_return
    defer lib.result_destroy(&result)
    expect_result(t, result, "", "", lib.Process_Exit(1)) or_return
    return true
}

@(test)
stdin :: proc(t: ^testing.T) {
    cmd, cmd_ok := lib.unwrap(lib.command_make("bash"))
    if !cmd_ok {return}
    defer lib.command_destroy(&cmd)
    cmd.opts.input = .Pipe
    lib.command_append(&cmd, "-c")
    lib.command_append(&cmd, "read TEST && echo $TEST")

    if process, process_ok := lib.unwrap(lib.command_run_async(cmd)); process_ok {
        if result, ok := run_pipe(t, &process); ok {
            expect_result(t, result, "", "")
            lib.result_destroy(&result)
        }
    }

    cmd.opts.output = .Silent
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd)); process_ok {
        if result, ok := run_pipe(t, &process); ok {
            expect_result(t, result, "", "")
            lib.result_destroy(&result)
        }
    }

    cmd.opts.output = .Capture
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd)); process_ok {
        if result, ok := run_pipe(t, &process); ok {
            expect_result(t, result, "Hello World" + NL, "")
            lib.result_destroy(&result)
        }
    }

    cmd.opts.output = .Capture_Combine
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd)); process_ok {
        if result, ok := run_pipe(t, &process); ok {
            expect_result(t, result, "Hello World" + NL, "")
            lib.result_destroy(&result)
        }
    }

    cmd.opts = {}
    cmd.opts.input = .Nothing
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd)); process_ok {
        run_nothing(t, &process)
    }

    cmd.opts.output = .Silent
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd)); process_ok {
        run_nothing(t, &process)
    }

    cmd.opts.output = .Capture
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd)); process_ok {
        run_nothing(t, &process)
    }

    cmd.opts.output = .Capture_Combine
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd)); process_ok {
        run_nothing(t, &process)
    }
}

