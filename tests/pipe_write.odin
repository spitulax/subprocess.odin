package tests

import lib ".."
import "core:testing"

// FIXME: See below
//@(test)
pipe_write :: proc(t: ^testing.T) {
    cmd, cmd_ok := lib.unwrap(
        lib.command_make("cat", lib.Exec_Opts{output = .Capture, input = .Pipe}),
        "`cat` was not found",
    )
    if !cmd_ok {return}
    defer lib.command_destroy(&cmd)

    process, process_ok := lib.unwrap(lib.command_run_async(cmd))
    if !process_ok || !expect_process(t, process) {return}

    STR :: "Hello, World!"
    written, write_ok := lib.unwrap(lib.pipe_write_string(process.stdin_pipe.?, STR, false))
    if !testing.expect_value(t, written, len(STR)) || !write_ok {return}

    // NOTE: `cat` would stop when the pipe is closed.
    // When `process_wait` is trying to close the pipe, it won't do that because the pipe has
    // already been closed here.
    // FIXME: On Windows, cat would still hang here
    destroy_ok := lib.unwrap(lib.pipe_destroy(&process.stdin_pipe.?))
    if !destroy_ok {return}

    result, result_ok := lib.unwrap(lib.process_wait(&process))
    if !result_ok {return}
    defer lib.result_destroy(&result)
    expect_result(t, result, STR + NL, "")
}

