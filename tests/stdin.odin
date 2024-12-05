package tests

import lib ".."
import "core:testing"

@(private = "file")
run_pipe :: proc(t: ^testing.T, process: ^lib.Process) -> (result: lib.Process_Result, ok: bool) {
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
    defer lib.process_result_destroy(&result)
    testing.expect_value(t, result.exit, 1) or_return
    testing.expect_value(t, result.stdout, "") or_return
    testing.expect_value(t, result.stderr, "") or_return
    return true
}

@(test)
stdin :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    cmd := lib.unwrap(lib.command_make("bash"))
    defer lib.command_destroy(&cmd)
    if !testing.expect(t, cmd.prog.found, "Bash was not found") {return}
    lib.command_append(&cmd, "-c")
    lib.command_append(&cmd, "read TEST && echo $TEST")

    if process, process_ok := lib.unwrap(lib.command_run_async(cmd, .Share, .Pipe)); process_ok {
        if result, ok := run_pipe(t, &process); ok {
            testing.expect_value(t, result.stdout, "")
            testing.expect_value(t, result.stderr, "")
            lib.process_result_destroy(&result)
        }
    }
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd, .Silent, .Pipe)); process_ok {
        if result, ok := run_pipe(t, &process); ok {
            testing.expect_value(t, result.stdout, "")
            testing.expect_value(t, result.stderr, "")
            lib.process_result_destroy(&result)
        }
    }
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd, .Capture, .Pipe)); process_ok {
        if result, ok := run_pipe(t, &process); ok {
            testing.expect_value(t, result.stdout, "Hello World" + NL)
            testing.expect_value(t, result.stderr, "")
            lib.process_result_destroy(&result)
        }
    }
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd, .Capture_Combine, .Pipe));
       process_ok {
        if result, ok := run_pipe(t, &process); ok {
            testing.expect_value(t, result.stdout, "Hello World" + NL)
            testing.expect_value(t, result.stderr, "")
            lib.process_result_destroy(&result)
        }
    }

    if process, process_ok := lib.unwrap(lib.command_run_async(cmd, .Share, .Nothing));
       process_ok {
        run_nothing(t, &process)
    }
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd, .Silent, .Nothing));
       process_ok {
        run_nothing(t, &process)
    }
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd, .Capture, .Nothing));
       process_ok {
        run_nothing(t, &process)
    }
    if process, process_ok := lib.unwrap(lib.command_run_async(cmd, .Capture_Combine, .Nothing));
       process_ok {
        run_nothing(t, &process)
    }
}

