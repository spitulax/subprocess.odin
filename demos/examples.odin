// WARNING: These examples are only supposed to be run on POSIX systems

package demos

import sp ".."
import "core:log"

main :: proc() {
    // Set the flag to print commands that are executed
    sp.default_flags_enable({.Echo_Commands_Debug})

    // Running a shell command
    {
        result, _ := sp.run_shell("echo Hello, World!")
        defer sp.result_destroy(&result)
        sp.log_info(result)
    }

    // Running a program (via `Command`)
    {
        cmd, _ := sp.command_make("cc") // Will search from PATH
        // File paths are also valid
        // prog := sp.command_make("./bin/cc")
        defer sp.command_destroy(&cmd)
        sp.command_append(&cmd, "--version")
        result, _ := sp.command_run(cmd)
        defer sp.result_destroy(&result)
        sp.log_info(result)
    }

    // Running a program (via `Program`)
    {
        prog := sp.program("cc") // Will search from PATH
        // File paths are also valid
        // prog := sp.program("./bin/cc")
        defer sp.program_destroy(&prog)
        result, _ := sp.program_run(prog, {"--version"})
        defer sp.result_destroy(&result)
        sp.log_info(result)
    }

    // Using `Command`
    {
        cmd, _ := sp.command_make("sh")
        defer sp.command_destroy(&cmd)

        // Appending to the default arguments
        sp.command_append(&cmd, "-c", "echo Hello, World!")
        // Setting default options
        cmd.opts.output = .Silent

        // Running with the default arguments and options
        sp.command_run(cmd, alloc = context.temp_allocator)

        // Resetting the default arguments
        sp.command_clear(&cmd)

        // Running with custom arguments and/or options
        sp.command_run(
            cmd,
            sp.Exec_Opts{output = .Share},
            {"-c", "echo Hello!"},
            alloc = context.temp_allocator,
        )
    }

    // Checking exit status
    {
        result, _ := sp.run_shell("exit 1")
        defer sp.result_destroy(&result)
        if !sp.result_success(result) {
            sp.log_info("Program exited abnormally:", result.exit)
        }
    }

    // Capturing output
    {
        // Separating stdout and stderr
        result, _ := sp.run_shell("echo Hello, World!>&2", {output = .Capture})
        sp.log_info(string(result.stdout))
        sp.log_info(string(result.stderr))
        sp.result_destroy(&result)

        // Combining stdout and stderr
        result, _ = sp.run_shell("echo Hello, World!>&2", {output = .Capture_Combine})
        sp.log_info(string(result.stdout))
        sp.result_destroy(&result)
    }

    // Silence output
    {
        result, _ := sp.run_shell("echo Hello, World", {output = .Silent})
        sp.log_info(result)
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
            sp.log_info(string(result.result.stdout))
        }
    }

    // Passing environment variables
    {
        result, _ := sp.run_shell_sync("echo $MY_VARIABLE", {extra_env = {"MY_VARIABLE=foobar"}})
        defer sp.result_destroy(&result)
        sp.log_info(result)
    }

    // Sending inputs
    {
        process, _ := sp.run_shell_async("read test && echo $test", {input = .Pipe})
        sp.pipe_write(process.stdin_pipe.?, "Hello, World!")
        result, _ := sp.process_wait(&process)
        defer sp.result_destroy(&result)
        sp.log_info(result)
    }

    // Custom pipes
    {
        stdout, _ := sp.pipe_make()
        defer sp.pipe_destroy(&stdout)
        process, _ := sp.run_shell_async(
            "echo Hello, World!",
            {output = .Capture_Combine, stdout_pipe = stdout},
        )
        result, _ := sp.process_wait(&process)
        defer sp.result_destroy(&result)
        output, _ := sp.pipe_read_all(&stdout)
        defer delete(output)
        sp.log_info(output)
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
        cmd, _ := sp.command_make("cc") // Will search from PATH
        // File paths are also valid
        // prog, _ := sp.command_make("./bin/cc")
        defer sp.command_destroy(&cmd)
        sp.command_append(&cmd, "--version")
        result, _ := sp.command_run(cmd, sp.Exec_Opts{output = .Capture})
        defer sp.result_destroy(&result)
        sp.log_info("Output:", string(result.stdout))
    }
}

