#+build linux, darwin, netbsd, openbsd, freebsd
#+private
package subprocess

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:time"


FAIL :: -1


Exit_Code :: distinct u32
Signal :: distinct posix.Signal
_Process_Exit :: union {
    Exit_Code,
    Signal,
}
_Process_Handle :: posix.pid_t

_is_success :: proc(exit: Process_Exit) -> bool {
    return exit == nil
}


_process_wait :: proc(
    self: Process,
    alloc: Alloc,
    loc: Loc,
) -> (
    result: Process_Result,
    err: Error,
) {
    defer if err != nil {
        process_result_destroy(&result)
    }

    for {
        status: i32
        child_pid := posix.waitpid(self.handle, &status, {})
        if child_pid == FAIL {
            err = General_Error.Process_Cannot_Exit
        }
        result.duration = time.since(self.execution_time)

        if posix.WIFSIGNALED(status) || posix.WIFEXITED(status) {
            stdout_pipe, stdout_pipe_ok := self.stdout_pipe.?
            stderr_pipe, stderr_pipe_ok := self.stderr_pipe.?
            if stdout_pipe_ok || stderr_pipe_ok {
                assert(
                    stderr_pipe_ok == stdout_pipe_ok,
                    "stdout and stderr pipe aren't equally initialized",
                )
                result.stdout = pipe_read(&stdout_pipe, loc, alloc) or_return
                result.stderr = pipe_read(&stderr_pipe, loc, alloc) or_return
                pipe_close_read(&stdout_pipe) or_return
                pipe_close_read(&stderr_pipe) or_return
            }

            if posix.WEXITSTATUS(status) == EARLY_EXIT_CODE {
                err = General_Error.Program_Not_Executed
            }
        }

        if posix.WIFEXITED(status) {
            exit_code := posix.WEXITSTATUS(status)
            result.exit = (exit_code == 0) ? nil : Exit_Code(exit_code)
            return
        }

        if posix.WIFSIGNALED(status) {
            result.exit = Signal(posix.WTERMSIG(status))
            return
        }
    }
}


_run_prog_async_unchecked :: proc(
    prog: string,
    args: []string,
    option: Run_Prog_Option = .Share,
    loc: Loc,
) -> (
    process: Process,
    err: Error,
) {
    stdout_pipe, stderr_pipe: _Pipe
    dev_null: posix.FD

    if option == .Silent {
        dev_null = posix.open("/dev/null", {.RDWR, .CREAT}, {.IWUSR, .IWGRP, .IWOTH})
        assert(posix.errno() == .NONE, "could not open /dev/null")
    } else if option == .Capture {
        pipe_init(&stdout_pipe) or_return
        pipe_init(&stderr_pipe) or_return
    }

    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    argv := make([]cstring, len(args) + 3)
    argv[0] = "/usr/bin/env"
    argv[1] = fmt.ctprint(prog)
    for &arg, i in args {
        argv[i + 2] = fmt.ctprintf("%s", arg)
    }
    argv[len(argv) - 1] = nil

    print_cmd(option, prog, args, loc)

    child_pid := posix.fork()
    if child_pid == FAIL {
        err = General_Error.Spawn_Failed
        return
    }

    if child_pid == 0 {
        wrap :: proc(err: Error) {
            if err != nil {
                // TODO: very naïve way to do this
                os.exit(EARLY_EXIT_CODE)
            }
        }

        switch option {
        case .Share:
            break
        case .Silent:
            wrap(fd_redirect(dev_null, posix.STDOUT_FILENO))
            wrap(fd_redirect(dev_null, posix.STDERR_FILENO))
            wrap(fd_close(dev_null))
        case .Capture:
            wrap(pipe_close_read(&stdout_pipe))
            wrap(pipe_close_read(&stderr_pipe))

            wrap(pipe_redirect(&stdout_pipe, posix.STDOUT_FILENO))
            wrap(pipe_redirect(&stderr_pipe, posix.STDERR_FILENO))

            wrap(pipe_close_write(&stdout_pipe))
            wrap(pipe_close_write(&stderr_pipe))
        }

        if posix.execve(argv[0], raw_data(argv), posix.environ) == FAIL {
            wrap(General_Error.Program_Not_Executed)
        }
        unreachable()
    }
    execution_time := time.now()

    if option == .Silent {
        fd_close(dev_null) or_return
    }

    delete(argv)
    maybe_stdout_pipe: Maybe(_Pipe) = (option == .Capture) ? stdout_pipe : nil
    maybe_stderr_pipe: Maybe(_Pipe) = (option == .Capture) ? stderr_pipe : nil
    return Process {
            handle = child_pid,
            execution_time = execution_time,
            stdout_pipe = maybe_stdout_pipe,
            stderr_pipe = maybe_stderr_pipe,
        },
        err
}


_program :: proc($name: string, loc: Loc) -> (found: bool) {
    res, err := run_prog_sync_unchecked(
        "sh",
        {"-c", "command -v " + name},
        .Silent,
        context.temp_allocator,
        loc,
    )
    return process_result_success(res) && err == nil
}


_Internal_Error :: enum u8 {
    None = 0,

    // `pipe_init`
    Pipe_Init_Failed,
    // `pipe_close_*`
    Pipe_Close_Failed,
    // `pipe_redirect`
    Pipe_Redirect_Failed,
    // `pipe_reaa`
    Pipe_Read_Failed,

    //  `fd_close`
    Fd_Close_Failed,
    // `fd_redirect`
    Fd_Redirect_Failed,
}


_Pipe :: struct #raw_union {
    array: Pipe_Both,
    struc: Pipe_Separate,
}
Pipe_Both :: [2]posix.FD
Pipe_Separate :: struct #align (size_of(posix.FD)) {
    read:  posix.FD,
    write: posix.FD,
}

@(require_results)
pipe_init :: proc(self: ^Pipe) -> (err: Error) {
    if posix.pipe(&self.array) == .FAIL {
        return Internal_Error.Pipe_Init_Failed
    }
    return nil
}

@(require_results)
pipe_close_read :: proc(self: ^Pipe) -> (err: Error) {
    if posix.close(self.struc.read) == .FAIL {
        return Internal_Error.Pipe_Close_Failed
    }
    return nil
}

@(require_results)
pipe_close_write :: proc(self: ^Pipe) -> (err: Error) {
    if posix.close(self.struc.write) == .FAIL {
        return Internal_Error.Pipe_Close_Failed
    }
    return nil
}

@(require_results)
pipe_redirect :: proc(self: ^Pipe, newfd: posix.FD) -> (err: Error) {
    if posix.dup2(self.struc.write, newfd) == FAIL {
        return Internal_Error.Pipe_Redirect_Failed
    }
    return nil
}

@(require_results)
pipe_read :: proc(
    self: ^Pipe,
    loc: Loc,
    alloc := context.allocator,
) -> (
    result: string,
    err: Error,
) {
    INITIAL_BUF_SIZE :: 1024
    pipe_close_write(self) or_return
    total_bytes_read := 0
    buf := make([dynamic]byte, INITIAL_BUF_SIZE)
    defer delete(buf)
    for {
        bytes_read := posix.read(
            self.struc.read,
            raw_data(buf[total_bytes_read:]),
            len(buf[total_bytes_read:]),
        )
        if bytes_read == 0 {
            break
        } else if bytes_read == FAIL {
            err = Internal_Error.Pipe_Read_Failed
            return
        }
        total_bytes_read += bytes_read
        if total_bytes_read >= len(buf) {
            resize(&buf, 2 * len(buf))
        }
    }
    result = strings.clone_from_bytes(buf[:total_bytes_read], alloc, loc)
    return
}


@(require_results)
fd_redirect :: proc(fd: posix.FD, newfd: posix.FD) -> (err: Internal_Error) {
    if posix.dup2(fd, newfd) == FAIL {
        return Internal_Error.Fd_Redirect_Failed
    }
    return nil
}

@(require_results)
fd_close :: proc(fd: posix.FD) -> (err: Internal_Error) {
    if posix.close(fd) == .FAIL {
        return Internal_Error.Fd_Close_Failed
    }
    return nil
}

