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
EARLY_EXIT_CODE :: 127


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
    self: ^Process,
    alloc: Alloc,
    loc: Loc,
) -> (
    result: Process_Result,
    err: Error,
) {
    defer if err != nil {
        process_result_destroy(&result)
    }
    defer self.alive = false

    for {
        status: i32
        child_pid := posix.waitpid(self.handle, &status, {.UNTRACED, .CONTINUED})
        if child_pid == FAIL {
            err = General_Error.Process_Cannot_Exit
        }
        result.duration = time.since(self.execution_time)

        if posix.WIFSIGNALED(status) || posix.WIFEXITED(status) {
            stdout_pipe, stdout_pipe_ok := self.stdout_pipe.?
            stderr_pipe, stderr_pipe_ok := self.stderr_pipe.?
            stdin_pipe, stdin_pipe_ok := self.stdin_pipe.?
            if stdout_pipe_ok {
                result.stdout = pipe_read(&stdout_pipe, loc, alloc) or_return
                pipe_close_read(&stdout_pipe) or_return
            }
            if stderr_pipe_ok {
                result.stderr = pipe_read(&stderr_pipe, loc, alloc) or_return
                pipe_close_read(&stderr_pipe) or_return
            }
            if stdin_pipe_ok {
                pipe_close_write(&stdin_pipe) or_return
                pipe_close_read(&stdin_pipe) or_return
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
    out_opt: Output_Option,
    in_opt: Input_Option,
    inherit_env: bool,
    extra_env: []string,
    loc: Loc,
) -> (
    process: Process,
    err: Error,
) {
    stdout_pipe, stderr_pipe, stdin_pipe: _Pipe
    dev_null: posix.FD

    switch out_opt {
    case .Share:
        break
    case .Silent:
        dev_null = posix.open("/dev/null", {.RDWR, .CREAT}, {.IWUSR, .IWGRP, .IWOTH})
        assert(posix.errno() == .NONE, "could not open /dev/null")
    case .Capture:
        pipe_init(&stdout_pipe) or_return
        pipe_init(&stderr_pipe) or_return
    case .Capture_Combine:
        pipe_init(&stdout_pipe) or_return
    }

    switch in_opt {
    case .Share:
        break
    case .Nothing:
        if dev_null == 0 {
            dev_null = posix.open("/dev/null", {.RDWR, .CREAT}, {.IWUSR, .IWGRP, .IWOTH})
            assert(posix.errno() == .NONE, "could not open /dev/null")
        }
    case .Pipe:
        pipe_init(&stdin_pipe) or_return
    }

    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    argv := make([]cstring, len(args) + 3)
    argv[0] = "/usr/bin/env"
    argv[1] = fmt.ctprint(prog)
    for &arg, i in args {
        argv[i + 2] = fmt.ctprintf("%s", arg)
    }
    argv[len(argv) - 1] = nil

    print_cmd(out_opt, in_opt, prog, args, loc)

    env := make([dynamic]cstring)
    if inherit_env {
        for i, x := 0, posix.environ[0]; x != nil; i, x = i + 1, posix.environ[i] {
            append(&env, x)
        }
    }
    for x in extra_env {
        append(&env, strings.clone_to_cstring(x, context.temp_allocator))
    }
    append(&env, nil)

    child_pid := posix.fork()
    if child_pid == FAIL {
        err = General_Error.Spawn_Failed
        return
    }

    if child_pid == 0 {
        wrap :: proc(err: Error) {
            if err != nil {
                os.exit(EARLY_EXIT_CODE)
            }
        }

        switch out_opt {
        case .Share:
            break
        case .Silent:
            wrap(fd_redirect(dev_null, posix.STDOUT_FILENO))
            wrap(fd_redirect(dev_null, posix.STDERR_FILENO))
        case .Capture:
            wrap(pipe_close_read(&stdout_pipe))
            wrap(pipe_close_read(&stderr_pipe))

            wrap(pipe_redirect_write(&stdout_pipe, posix.STDOUT_FILENO))
            wrap(pipe_redirect_write(&stderr_pipe, posix.STDERR_FILENO))

            wrap(pipe_close_write(&stdout_pipe))
            wrap(pipe_close_write(&stderr_pipe))
        case .Capture_Combine:
            wrap(pipe_close_read(&stdout_pipe))

            wrap(pipe_redirect_write(&stdout_pipe, posix.STDOUT_FILENO))
            wrap(fd_redirect(posix.STDOUT_FILENO, posix.STDERR_FILENO))

            wrap(pipe_close_write(&stdout_pipe))
        }

        switch in_opt {
        case .Share:
            break
        case .Nothing:
            wrap(fd_redirect(dev_null, posix.STDIN_FILENO))
        case .Pipe:
            wrap(pipe_close_write(&stdin_pipe))
            wrap(pipe_redirect_read(&stdin_pipe, posix.STDIN_FILENO))
            wrap(pipe_close_read(&stdin_pipe))
        }

        if out_opt == .Silent || in_opt == .Nothing {
            fd_close(dev_null) or_return
        }

        if posix.execve(argv[0], raw_data(argv), raw_data(env)) == FAIL {
            wrap(General_Error.Program_Not_Executed)
        }
        unreachable()
    }
    process.execution_time = time.now()
    process.alive = true

    delete(env)
    delete(argv)

    if out_opt == .Silent || in_opt == .Nothing {
        fd_close(dev_null) or_return
    }
    switch out_opt {
    case .Share, .Silent:
        process.stdout_pipe = nil
        process.stderr_pipe = nil
    case .Capture:
        process.stdout_pipe = stdout_pipe
        process.stderr_pipe = stderr_pipe
    case .Capture_Combine:
        process.stdout_pipe = stdout_pipe
        process.stderr_pipe = nil
    }
    if in_opt == .Pipe {
        process.stdin_pipe = stdin_pipe
    }
    process.handle = child_pid
    return
}


_program :: proc(name: string, loc: Loc) -> Error {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    if res, err := run_prog_sync_unchecked(
        "sh",
        {"-c", fmt.tprint("command -v", name)},
        .Silent,
        alloc = context.temp_allocator,
        loc = loc,
    ); !process_result_success(res) {
        return General_Error.Program_Not_Found
    } else {
        return err
    }
}


_Internal_Error :: enum u8 {
    None = 0,
    // Failed to initialise the pipe
    Pipe_Init_Failed,
    // Failed to close the pipe
    Pipe_Close_Failed,
    // Failed to redirect pipes
    Pipe_Redirect_Failed,
    // Failed to read from the pipe
    Pipe_Read_Failed,
    // Failed to close the file descriptor
    Fd_Close_Failed,
    // Failed to redirect file descriptors
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
pipe_redirect_read :: proc(self: ^Pipe, newfd: posix.FD) -> (err: Error) {
    if posix.dup2(self.struc.read, newfd) == FAIL {
        return Internal_Error.Pipe_Redirect_Failed
    }
    return nil
}

@(require_results)
pipe_redirect_write :: proc(self: ^Pipe, newfd: posix.FD) -> (err: Error) {
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
    buf := make([dynamic]byte, INITIAL_BUF_SIZE, alloc)
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
    resize(&buf, total_bytes_read)
    return string(buf[:]), nil
}

@(require_results)
_pipe_write_buf :: proc(self: Pipe, buf: []byte) -> (n: int, err: Error) {
    if n = posix.write(self.struc.write, raw_data(buf), len(buf)); n == FAIL {
        err = General_Error.Pipe_Write_Failed
        return
    } else {
        return n, nil
    }
}

@(require_results)
_pipe_write_string :: proc(self: Pipe, str: string) -> (n: int, err: Error) {
    if n = posix.write(self.struc.write, raw_data(str), len(str)); n == FAIL {
        err = General_Error.Pipe_Write_Failed
        return
    } else {
        return n, nil
    }
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

