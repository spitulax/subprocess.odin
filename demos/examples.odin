package demos
// TODO: UPDATE EXAMPLES

import sp ".."
import "core:log"

main :: proc() {
    // Set the flag to print commands that are executed
    sp.default_flags_enable({.Echo_Commands_Debug})

    // Running a shell command
    {
        result, err := sp.run_shell_sync("echo Hello, World!")
        defer sp.result_destroy(&result)
        if err == nil {
            sp.log_info(result)
        }
    }

    // Running a program
    {
        prog := sp.program("cc") // Will search from PATH
        // File paths are also valid
        // prog := sp.program("./bin/cc")
        if !prog.found {return}
        result, err := sp.run_prog_sync(prog, {"--version"})
        defer sp.process_result_destroy(&result)
        if err == nil {
            sp.log_info(result)
        }
    }

    // Checking exit status
    {
        result, err := sp.run_shell_sync("exit 1")
        defer sp.process_result_destroy(&result)
        if err == nil {
            if !sp.process_result_success(result) {
                sp.log_info("Program exited abnormally:", result.exit)
            }
        }
    }

    // Capturing output
    {
        // Separating stdout and stderr
        result, err := sp.run_shell_sync("echo Hello, World!>&2", out_opt = .Capture)
        if err == nil {
            sp.log_info(result.stdout)
            sp.log_info(result.stderr)
        }
        sp.process_result_destroy(&result)

        // Combining stdout and stderr
        result, err = sp.run_shell_sync("echo Hello, World!>&2", out_opt = .Capture_Combine)
        if err == nil {
            sp.log_info(result.stdout)
        }
        sp.process_result_destroy(&result)
    }

    // Silence output
    {
        result, err := sp.run_shell_sync("echo Hello, World", out_opt = .Silent)
        if err == nil {
            sp.log_info(result)
        }
    }

    // Parallel execution
    {
        processes: [10]sp.Process
        for &process in processes {
            process, _ = sp.run_shell_async("echo HELLO, WORLD!", .Capture)
        }
        results := sp.process_wait_many(processes[:])
        defer sp.process_result_destroy_many(results.result[:len(results)])
        for result in results {
            if result.err == nil {
                sp.log_info(result.result.stdout)
            }
        }
    }

    // Command builder
    {
        cmd, cmd_err := sp.command_make("cc")
        if cmd_err != nil {return}
        defer sp.command_destroy(&cmd)
        if !cmd.prog.found {return}
        sp.command_append(&cmd, "--version")
        result, result_err := sp.command_run_sync(cmd)
        if result_err == nil {
            sp.log_info(result)
        }
    }

    // Passing environment variables
    {
        result, err := sp.run_shell_sync(
            "echo $MY_VARIABLE",
            // "echo %MY_VARIABLE", (Windows)
            extra_env = {"MY_VARIABLE=foobar"},
        )
        defer sp.process_result_destroy(&result)
        if err == nil {
            sp.log_info(result)
        }
    }

    // Sending inputs
    {
        process, process_err := sp.run_shell_async("read test && echo $test", in_opt = .Pipe)
        if process_err != nil {return}
        sp.pipe_write(process.stdin_pipe.?, "Hello, World!")
        result, result_err := sp.process_wait(&process)
        defer sp.process_result_destroy(&result)
        if result_err == nil {
            sp.log_info(result)
        }
    }

    // Using the library's logger
    {
        context.logger = sp.create_logger()
        sp.log_info("Hello!")
        // Now it's the same as
        log.info("Hello!")
    }
}

