package tests

import lib ".."
import "core:os"
import "core:testing"

@(private = "file")
FILE :: "subprocess.odin"

@(test)
pipe_read :: proc(t: ^testing.T) {
    file_content, file_content_err := os.read_entire_file_from_filename_or_err(FILE)
    if !testing.expectf(
        t,
        file_content_err == nil,
        "Could not open " + FILE + ": %v",
        file_content_err,
    ) {return}
    defer delete(file_content)

    cmd, cmd_ok := lib.unwrap(
        lib.command_make("cat", lib.Exec_Opts{output = .Capture}),
        "`cat` was not found",
    )
    if !cmd_ok {return}
    defer lib.command_destroy(&cmd)
    lib.command_append(&cmd, FILE)

    process, process_ok := lib.unwrap(lib.command_run_async(cmd))
    if !process_ok || !expect_process(t, process) {return}

    output, output_ok := lib.unwrap(lib.pipe_read_all(&process.stdout_pipe.?))
    if !output_ok {return}
    defer delete(output)

    testing.expect_value(t, string(output), string(file_content))

    result, result_ok := lib.unwrap(lib.process_wait(&process))
    if !result_ok {return}
    defer lib.result_destroy(&result)
    expect_result(t, result, "", "")
}

