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
// Random numbers that are hopefully never used by any program.
// This is a little bit weird because for now, the only way for a child process
// to send information to its parent is by return code.
// Using something like shared memory may work, but it would have to be explicitly
// deallocated by the user.
EXIT_CWD_FAILED :: 210
EXIT_PIPE_FAILED :: 211
EXIT_EXECVE_FAILED :: 212


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
    read_stdout, read_stderr :=
        stdout_pipe_ok &&
        stdout_pipe.struc.read != -1,
        stderr_pipe_ok &&
        stderr_pipe.struc.read != -1
    stdout_buf, stderr_buf: [dynamic]byte
    INITIAL_BUF_CAP :: 1 * mem.Kilobyte
    if read_stdout {
        pipe_close_write(stdout_pipe) or_return
        stdout_buf = make([dynamic]byte, 0, INITIAL_BUF_CAP, alloc)
    }
    if read_stderr {
        pipe_close_write(stderr_pipe) or_return
        stderr_buf = make([dynamic]byte, 0, INITIAL_BUF_CAP, alloc)
    }
    defer if err != nil && stdout_pipe_ok {
        delete(stdout_buf)
    }
    defer if err != nil && stderr_pipe_ok {
        delete(stderr_buf)
    }

    for {
        for read_stdout || read_stderr {
            bytes_read: uint
            if read_stdout {
                bytes_read += _pipe_read(stdout_pipe, &stdout_buf, loc) or_return
            }
            if read_stderr {
                bytes_read += _pipe_read(stderr_pipe, &stderr_buf, loc) or_return
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
            if stdout_pipe_ok {
                pipe_ensure_closed(stdout_pipe) or_return
            }
            if stderr_pipe_ok {
                pipe_ensure_closed(stderr_pipe) or_return
            }
            if stdin_pipe_ok {
                pipe_ensure_closed(stdin_pipe) or_return
            }

            switch posix.WEXITSTATUS(status) {
            case EXIT_CWD_FAILED:
                err = Internal_Error.Set_Cwd_Failed
            case EXIT_PIPE_FAILED:
                err = Internal_Error.Pipe_Failed
            case EXIT_EXECVE_FAILED:
                err = Internal_Error.Execve_Failed
            case:
                if stdout_pipe_ok {
                    result.stdout = stdout_buf[:]
                }
                if stderr_pipe_ok {
                    result.stderr = stderr_buf[:]
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
    // NOTE: Any of these pipes could be equal to a pipe from `opts` if `opts`'s pipe is initialised.
    // Thus, this procedure or the waiting procedure should not close the pipe from `opts`.
    stdout_pipe, stderr_pipe, stdin_pipe: _Pipe
    dev_null: posix.FD = -1

    switch opts.output {
    case .Share:
        break
    case .Silent:
        open_dev_null(&dev_null)
    case .Capture:
        if opts.stdout_pipe == nil {
            pipe_init(&stdout_pipe) or_return
        } else {
            stdout_pipe = opts.stdout_pipe.?
        }
        if opts.stderr_pipe == nil {
            pipe_init(&stderr_pipe) or_return
        } else {
            stderr_pipe = opts.stderr_pipe.?
        }
    case .Capture_Combine:
        if opts.stdout_pipe == nil {
            pipe_init(&stdout_pipe) or_return
        } else {
            stdout_pipe = opts.stdout_pipe.?
        }
    }

    switch opts.input {
    case .Share:
        break
    case .Nothing:
        open_dev_null(&dev_null)
    case .Pipe:
        if opts.stdin_pipe == nil {
            pipe_init(&stdin_pipe) or_return
        } else {
            stdin_pipe = opts.stdin_pipe.?
        }
    }

    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    argv := make([]cstring, len(args) + 2)
    argv[0] = fmt.ctprint(prog)
    for &arg, i in args {
        argv[i + 1] = fmt.ctprintf("%s", arg)
    }
    argv[len(argv) - 1] = nil

    echo_command(opts, .POSIX, prog, args, loc)

    env: [^]cstring
    env_cap := -1
    if !opts.zero_env && len(opts.extra_env) == 0 {
        env = posix.environ
    } else if opts.zero_env && len(opts.extra_env) == 0 {
        env = raw_data([]cstring{nil})
    } else {
        env_arr := make([dynamic]cstring)
        if !opts.zero_env {
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
        unwrap :: proc(err: Error) {
            if err != nil {
                os.exit(EXIT_PIPE_FAILED)
            }
        }

        if opts.cwd != "" && os.set_current_directory(opts.cwd) != nil {
            os.exit(EXIT_CWD_FAILED)
        }

        switch opts.output {
        case .Share:
            break
        case .Silent:
            unwrap(fd_redirect(dev_null, posix.STDOUT_FILENO))
            unwrap(fd_redirect(dev_null, posix.STDERR_FILENO))
        case .Capture:
            unwrap(pipe_close_read(&stdout_pipe))
            unwrap(pipe_close_read(&stderr_pipe))

            unwrap(pipe_redirect_write(&stdout_pipe, posix.STDOUT_FILENO))
            unwrap(pipe_redirect_write(&stderr_pipe, posix.STDERR_FILENO))

            unwrap(pipe_close_write(&stdout_pipe))
            unwrap(pipe_close_write(&stderr_pipe))
        case .Capture_Combine:
            unwrap(pipe_close_read(&stdout_pipe))

            unwrap(pipe_redirect_write(&stdout_pipe, posix.STDOUT_FILENO))
            unwrap(fd_redirect(posix.STDOUT_FILENO, posix.STDERR_FILENO))

            unwrap(pipe_close_write(&stdout_pipe))
        }

        switch opts.input {
        case .Share:
            break
        case .Nothing:
            unwrap(fd_redirect(dev_null, posix.STDIN_FILENO))
        case .Pipe:
            unwrap(pipe_close_write(&stdin_pipe))
            unwrap(pipe_redirect_read(&stdin_pipe, posix.STDIN_FILENO))
            unwrap(pipe_close_read(&stdin_pipe))
        }

        close_dev_null(&dev_null)

        if posix.execve(argv[0], raw_data(argv), env) == FAIL {
            os.exit(EXIT_EXECVE_FAILED)
        }
        unreachable()
    }
    process.execution_time = time.now()
    process.alive = true

    if env_cap >= 0 {
        runtime.mem_free_with_size(env, env_cap * size_of(cstring))
    }
    delete(argv)

    close_dev_null(&dev_null)

    switch opts.output {
    case .Share, .Silent:
        process.stdout_pipe = nil
        process.stderr_pipe = nil
    case .Capture:
        process.stdout_pipe = stdout_pipe if opts.stdout_pipe == nil else nil
        process.stderr_pipe = stderr_pipe if opts.stderr_pipe == nil else nil
    case .Capture_Combine:
        process.stdout_pipe = stdout_pipe if opts.stdout_pipe == nil else nil
        process.stderr_pipe = nil
    }
    if opts.input == .Pipe {
        process.stdin_pipe = stdin_pipe if opts.stdin_pipe == nil else nil
    }
    process.opts = opts
    process.handle = child_pid
    return
}


_program :: proc(name: string, alloc: Alloc, loc: Loc) -> (path: string, err: Error) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(alloc == context.temp_allocator)
    res: Result
    res = exec(
        "/bin/sh",
        {"-c", fmt.tprintf("command -v '%s'", name)},
        {output = .Capture, dont_echo_command = true},
        alloc = context.temp_allocator,
    ) or_return

    if !result_success(res) {
        err = General_Error.Program_Not_Found
        return
    }

    path = strings.clone(trim_nl(string(res.stdout)), alloc, loc)
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
    // General pipe operations failure
    Pipe_Failed,
    // Failed to set working directory for the process.
    Set_Cwd_Failed,
    // `execve` returned
    Execve_Failed,
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
@(private = "file")
pipe_init :: proc(self: ^Pipe) -> (err: Error) {
    if posix.pipe(&self.array) == .FAIL {
        return Internal_Error.Pipe_Init_Failed
    }
    return nil
}

_pipe_init :: proc(self: ^Pipe) -> (err: Error) {
    pipe_init(self) or_return
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

@(require_results)
pipe_ensure_closed :: proc(self: ^Pipe) -> (err: Error) {
    pipe_close_read(self) or_return
    self.struc.read = -1
    pipe_close_write(self) or_return
    self.struc.write = -1
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
_pipe_read :: proc(self: ^Pipe, buf: ^[dynamic]byte, loc: Loc) -> (bytes_read: uint, err: Error) {
    if self.struc.read == -1 {return}
    pipe_close_write(self) or_return
    init_len: uint = len(buf)
    defer if err != nil {
        resize(buf, init_len)
    }
    for (_pipe_read_once(self, buf, loc) or_return) != 0 {}
    assert(init_len <= len(buf))
    return len(buf) - init_len, nil
}

_pipe_read_once :: proc {
    _pipe_read_once_append,
    _pipe_read_once_non_append,
}

@(require_results)
_pipe_read_once_append :: proc(
    self: ^Pipe,
    buf: ^[dynamic]byte,
    loc: Loc,
) -> (
    bytes_read: uint,
    err: Error,
) {
    if self.struc.read == -1 {return}
    pipe_close_write(self) or_return
    slice := raw_data(buf^)[len(buf):]
    int_bytes_read := posix.read(self.struc.read, slice, cap(buf) - len(buf))
    if int_bytes_read == 0 {
        return
    } else if int_bytes_read == FAIL {
        err = Internal_Error.Pipe_Read_Failed
        return
    }
    bytes_read = uint(int_bytes_read)
    non_zero_resize(buf, len(buf) + int(bytes_read))
    if len(buf) >= cap(buf) {
        reserve(buf, 2 * cap(buf))
    }
    return
}

@(require_results)
_pipe_read_once_non_append :: proc(
    self: ^Pipe,
    buf: []byte,
    loc := #caller_location,
) -> (
    bytes_read: uint,
    err: Error,
) {
    if self.struc.read == -1 {return}
    pipe_close_write(self) or_return
    int_bytes_read := posix.read(self.struc.read, raw_data(buf), len(buf))
    if int_bytes_read == 0 {
        return
    } else if int_bytes_read == FAIL {
        err = Internal_Error.Pipe_Read_Failed
        return
    }
    bytes_read = uint(int_bytes_read)
    return
}

@(require_results)
_pipe_write_buf :: proc(self: Pipe, buf: []byte) -> (n: uint, err: Error) {
    if self.struc.write == -1 {return}
    if written := posix.write(self.struc.write, raw_data(buf), len(buf)); written <= FAIL {
        err = General_Error.Pipe_Write_Failed
        return
    } else {
        return uint(written), nil
    }
}

@(require_results)
_pipe_write_string :: proc(self: Pipe, str: string) -> (n: uint, err: Error) {
    if self.struc.write == -1 {return}
    if written := posix.write(self.struc.write, raw_data(str), len(str)); written <= FAIL {
        err = General_Error.Pipe_Write_Failed
        return
    } else {
        return uint(written), nil
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
fd_close :: proc(fd: posix.FD) -> (err: Internal_Error) {
    if fd == -1 {return}
    if posix.close(fd) == .FAIL {
        return Internal_Error.Fd_Close_Failed
    }
    return nil
}


open_dev_null :: proc(fd: ^posix.FD) {
    if fd^ == -1 {
        fd^ = posix.open(
            "/dev/null",
            {.RDWR, .CREAT},
            {.IWUSR, .IWGRP, .IWOTH, .IRUSR, .IRGRP, .IROTH},
        )
        assert(posix.errno() == .NONE, "could not open /dev/null")
    }
}

close_dev_null :: proc(fd: ^posix.FD) {
    if fd^ == -1 {return}
    assert(fd_close(fd^) == nil, "could not close /dev/null")
    fd^ = -1
}

