#+build linux, darwin, netbsd, openbsd, freebsd
#+private
package subprocess

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:time"


FAIL :: -1
EARLY_EXIT_CODE :: 211 // Just a random number that is hopefully never be used by any program


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


_process_wait :: proc(self: ^Process, alloc: Alloc, loc: Loc) -> (result: Result, err: Error) {
    defer if err != nil {
        result_destroy(&result, alloc)
    }
    defer {
        self.stdout_pipe = nil
        self.stderr_pipe = nil
        self.stdin_pipe = nil
    }

    stdout_pipe, stdout_pipe_ok := &self.stdout_pipe.?
    stderr_pipe, stderr_pipe_ok := &self.stderr_pipe.?
    stdin_pipe, stdin_pipe_ok := &self.stdin_pipe.?
    stdout_buf, stderr_buf: [dynamic]byte
    defer if stdout_pipe_ok {
        delete(stdout_buf)
    }
    defer if stderr_pipe_ok {
        delete(stderr_buf)
    }
    stdout_bytes_read, stderr_bytes_read: uint
    INITIAL_BUF_SIZE :: 1 * mem.Kilobyte
    if stdout_pipe_ok {
        pipe_close_write(stdout_pipe) or_return
        stdout_buf = make([dynamic]byte, INITIAL_BUF_SIZE, alloc)
    }
    if stderr_pipe_ok {
        pipe_close_write(stderr_pipe) or_return
        stderr_buf = make([dynamic]byte, INITIAL_BUF_SIZE, alloc)
    }

    for {
        for {
            bytes_read: uint
            if stdout_pipe_ok {
                bytes_read += pipe_read(
                    stdout_pipe,
                    &stdout_buf,
                    &stdout_bytes_read,
                    loc,
                ) or_return
            }
            if stderr_pipe_ok {
                bytes_read += pipe_read(
                    stderr_pipe,
                    &stderr_buf,
                    &stderr_bytes_read,
                    loc,
                ) or_return
            }
            if bytes_read == 0 {
                break
            }
        }

        status: i32
        child_pid := posix.waitpid(self.handle, &status, {.UNTRACED, .CONTINUED})
        if child_pid == FAIL {
            err = General_Error.Process_Cannot_Exit
        }
        result.duration = time.since(self.execution_time)
        self.alive = false

        if posix.WIFSIGNALED(status) || posix.WIFEXITED(status) {
            if posix.WEXITSTATUS(status) == EARLY_EXIT_CODE {
                err = General_Error.Program_Not_Executed
            } else {
                if stdout_pipe_ok {
                    pipe_ensure_closed(stdout_pipe) or_return
                    result.stdout = strings.clone_from_bytes(stdout_buf[:stdout_bytes_read], alloc)
                }
                if stderr_pipe_ok {
                    pipe_ensure_closed(stderr_pipe) or_return
                    result.stderr = strings.clone_from_bytes(stderr_buf[:stderr_bytes_read], alloc)
                }
                if stdin_pipe_ok {
                    pipe_ensure_closed(stdin_pipe) or_return
                }
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


_exec_async :: proc(
    prog: string,
    args: []string,
    opts: Exec_Opts,
    loc: Loc,
) -> (
    process: Process,
    err: Error,
) {
    stdout_pipe, stderr_pipe, stdin_pipe: _Pipe
    dev_null: posix.FD

    switch opts.output {
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

    switch opts.input {
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
    argv := make([]cstring, len(args) + 2)
    argv[0] = fmt.ctprint(prog)
    for &arg, i in args {
        argv[i + 1] = fmt.ctprintf("%s", arg)
    }
    argv[len(argv) - 1] = nil

    print_cmd(opts, .POSIX, prog, args, loc)

    env: [^]cstring
    env_cap := -1
    if opts.inherit_env && len(opts.extra_env) == 0 {
        env = posix.environ
    } else if !opts.inherit_env && len(opts.extra_env) == 0 {
        env = raw_data([]cstring{nil})
    } else {
        env_arr := make([dynamic]cstring)
        if opts.inherit_env {
            for i, x := 0, posix.environ[0]; x != nil; i, x = i + 1, posix.environ[i] {
                append(&env_arr, x)
            }
        }
        for x in opts.extra_env {
            append(&env_arr, strings.clone_to_cstring(x, context.temp_allocator))
        }
        append(&env_arr, nil)
        env = raw_data(env_arr)
        env_cap = cap(env_arr)
    }

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

        switch opts.output {
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

        switch opts.input {
        case .Share:
            break
        case .Nothing:
            wrap(fd_redirect(dev_null, posix.STDIN_FILENO))
        case .Pipe:
            wrap(pipe_close_write(&stdin_pipe))
            wrap(pipe_redirect_read(&stdin_pipe, posix.STDIN_FILENO))
            wrap(pipe_close_read(&stdin_pipe))
        }

        if opts.output == .Silent || opts.input == .Nothing {
            fd_close(&dev_null) or_return
        }

        if posix.execve(argv[0], raw_data(argv), env) == FAIL {
            wrap(General_Error.Program_Not_Executed)
        }
        unreachable()
    }
    process.execution_time = time.now()
    process.alive = true

    if env_cap >= 0 {
        runtime.mem_free_with_size(env, env_cap * size_of(cstring))
    }
    delete(argv)

    if opts.output == .Silent || opts.input == .Nothing {
        fd_close(&dev_null) or_return
    }
    switch opts.output {
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
    if opts.input == .Pipe {
        process.stdin_pipe = stdin_pipe
    }
    process.handle = child_pid
    return
}


_program :: proc(name: string, alloc: Alloc, loc: Loc) -> (path: string, err: Error) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(alloc == context.temp_allocator)
    res: Result
    if res, err = exec(
        "/bin/sh",
        {"-c", fmt.tprintf("command -v '%s'", name)},
        {output = .Capture, inherit_env = true},
        alloc = context.temp_allocator,
        loc = loc,
    ); err != nil {
        return
    }
    if !result_success(res) {
        err = General_Error.Program_Not_Found
        return
    }

    path = strings.clone(res.stdout[:len(res.stdout) - 1], alloc, loc)
    return
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
    if self.struc.read == -1 {return}
    if posix.close(self.struc.read) == .FAIL {
        return Internal_Error.Pipe_Close_Failed
    }
    self.struc.read = -1
    return nil
}

@(require_results)
pipe_close_write :: proc(self: ^Pipe) -> (err: Error) {
    if self.struc.write == -1 {return}
    if posix.close(self.struc.write) == .FAIL {
        return Internal_Error.Pipe_Close_Failed
    }
    self.struc.write = -1
    return nil
}

pipe_ensure_closed :: proc(self: ^Pipe) -> (err: Error) {
    pipe_close_read(self) or_return
    pipe_close_write(self) or_return
    self^ = {}
    return nil
}

@(require_results)
pipe_redirect_read :: proc(self: ^Pipe, newfd: posix.FD) -> (err: Error) {
    if self.struc.read == -1 || newfd == -1 {return}
    if posix.dup2(self.struc.read, newfd) == FAIL {
        return Internal_Error.Pipe_Redirect_Failed
    }
    return nil
}

@(require_results)
pipe_redirect_write :: proc(self: ^Pipe, newfd: posix.FD) -> (err: Error) {
    if self.struc.write == -1 || newfd == -1 {return}
    if posix.dup2(self.struc.write, newfd) == FAIL {
        return Internal_Error.Pipe_Redirect_Failed
    }
    return nil
}

@(require_results)
pipe_read :: proc(
    self: ^Pipe,
    buf: ^[dynamic]byte,
    total_bytes_read: ^uint,
    loc: Loc,
) -> (
    bytes_read: uint,
    err: Error,
) {
    if self.struc.read == -1 {return}
    init_len := total_bytes_read^
    defer if err != nil {
        resize(buf, init_len)
    }
    for {
        loop_bytes_read := posix.read(
            self.struc.read,
            raw_data(buf[total_bytes_read^:]),
            len(buf[total_bytes_read^:]),
        )
        if loop_bytes_read == 0 {
            break
        } else if loop_bytes_read == FAIL {
            err = Internal_Error.Pipe_Read_Failed
            return
        }
        total_bytes_read^ += uint(loop_bytes_read)
        if total_bytes_read^ >= len(buf) {
            resize(buf, 2 * len(buf))
        }
    }
    return total_bytes_read^ - init_len, nil
}

@(require_results)
_pipe_write_buf :: proc(self: Pipe, buf: []byte) -> (n: int, err: Error) {
    if self.struc.write == -1 {return}
    if n = posix.write(self.struc.write, raw_data(buf), len(buf)); n == FAIL {
        err = General_Error.Pipe_Write_Failed
        return
    } else {
        return n, nil
    }
}

@(require_results)
_pipe_write_string :: proc(self: Pipe, str: string) -> (n: int, err: Error) {
    if self.struc.write == -1 {return}
    if n = posix.write(self.struc.write, raw_data(str), len(str)); n == FAIL {
        err = General_Error.Pipe_Write_Failed
        return
    } else {
        return n, nil
    }
}


@(require_results)
fd_redirect :: proc(fd: posix.FD, newfd: posix.FD) -> (err: Internal_Error) {
    if fd == -1 || newfd == -1 {return}
    if posix.dup2(fd, newfd) == FAIL {
        return Internal_Error.Fd_Redirect_Failed
    }
    return nil
}

@(require_results)
fd_close :: proc(fd: ^posix.FD) -> (err: Internal_Error) {
    if fd^ == -1 {return}
    if posix.close(fd^) == .FAIL {
        return Internal_Error.Fd_Close_Failed
    }
    fd^ = -1
    return nil
}

