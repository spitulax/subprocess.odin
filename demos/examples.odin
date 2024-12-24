package demos

import sp ".."
import "core:log"

main :: proc() {
    // Set the flag to print commands that are executed
    sp.default_flags_enable({.Echo_Commands_Debug})

    // Running a shell command
    {
        result, err := sp.run_shell("echo Hello, World!")
        if err != nil {return}
        defer sp.result_destroy(&result)
        sp.log_info(result)
    }

    // Running a program (via `Command`)
    {
        cmd, cmd_err := sp.command_make("cc") // Will search from PATH
        // File paths are also valid
        // prog := sp.command_make("./bin/cc")
        if cmd_err != nil {return}
        defer sp.command_destroy(&cmd)
        sp.command_append(&cmd, "--version")
        result, result_err := sp.command_run(cmd)
        if result_err != nil {return}
        defer sp.result_destroy(&result)
        sp.log_info(result)
    }

    // Running a program (via `Program`)
    {
        prog := sp.program("cc") // Will search from PATH
        // File paths are also valid
        // prog := sp.program("./bin/cc")
        defer sp.program_destroy(&prog)
        result, result_err := sp.program_run(prog, {"--version"})
        if result_err != nil {return}
        defer sp.result_destroy(&result)
        sp.log_info(result)
    }

    // Using `Command`
    {
        cmd, cmd_err := sp.command_make("sh")
        if cmd_err != nil {return}
        defer sp.command_destroy(&cmd)

        // Appending to the default arguments
        sp.command_append(&cmd, "-c", "echo Hello, World!")
        // Setting default options
        cmd.opts.output = .Silent

        // Running with the default arguments and options
        if _, err := sp.command_run(cmd, alloc = context.temp_allocator); err != nil {return}

        // Resetting the default arguments
        sp.command_clear(&cmd)

        // Running with custom arguments and/or options
        if _, err := sp.command_run(
            cmd,
            sp.Exec_Opts{output = .Share},
            {"-c", "echo Hello!"},
            alloc = context.temp_allocator,
        ); err != nil {return}
    }

    // Checking exit status
    {
        result, result_err := sp.run_shell("exit 1")
        if result_err != nil {return}
        defer sp.result_destroy(&result)
        if !sp.result_success(result) {
            sp.log_info("Program exited abnormally:", result.exit)
        }
    }

    // Capturing output
    {
        // Separating stdout and stderr
        result, err := sp.run_shell("echo Hello, World!>&2", {output = .Capture})
        if err == nil {
            sp.log_info(string(result.stdout))
            sp.log_info(string(result.stderr))
        }
        sp.result_destroy(&result)

        // Combining stdout and stderr
        result, err = sp.run_shell("echo Hello, World!>&2", {output = .Capture_Combine})
        if err == nil {
            sp.log_info(string(result.stdout))
        }
        sp.result_destroy(&result)
    }

    // Silence output
    {
        result, err := sp.run_shell("echo Hello, World", {output = .Silent})
        if err == nil {
            sp.log_info(result)
        }
    }

    // Parallel execution
    {
        processes: [10]sp.Process
        for &process in processes {
            process, _ = sp.run_shell_async("echo HELLO, WORLD!", {output = .Capture})
        }
        results := sp.process_wait_many(processes[:])
        defer sp.result_destroy_many(&results)
        for result in results {
            if result.err == nil {
                sp.log_info(string(result.result.stdout))
            }
        }
    }

    // Passing environment variables
    {
        result, err := sp.run_shell_sync("echo $MY_VARIABLE", {extra_env = {"MY_VARIABLE=foobar"}})
        defer sp.result_destroy(&result)
        if err == nil {
            sp.log_info(result)
        }
    }

    // Sending inputs
    {
        process, process_err := sp.run_shell_async("read test && echo $test", {input = .Pipe})
        if process_err != nil {return}
        sp.pipe_write(process.stdin_pipe.?, "Hello, World!")
        result, result_err := sp.process_wait(&process)
        if result_err != nil {return}
        defer sp.result_destroy(&result)
        sp.log_info(result)
    }

    // Using the library's logger
    {
        context.logger = sp.create_logger()
        sp.log_info("Hello!")
        // Now it's the same as
        log.info("Hello!")
    }

    // Example from README.md
    {
        cmd, cmd_err := sp.command_make("cc") // Will search from PATH
        // File paths are also valid
        // prog := sp.command_make("./bin/cc")
        if cmd_err != nil {return}
        defer sp.command_destroy(&cmd)
        sp.command_append(&cmd, "--version")
        result, result_err := sp.command_run(cmd, sp.Exec_Opts{output = .Capture})
        if result_err != nil {return}
        defer sp.result_destroy(&result)
        sp.log_info("Output:", string(result.stdout))
    }
}

