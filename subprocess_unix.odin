#+build linux, darwin, netbsd, openbsd, freebsd
package subprocess

import "core:c/libc"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:time"


FAIL :: -1
Errno :: posix.Errno


_Exit :: distinct u32
_Signal :: distinct posix.Signal
_Process_Exit :: union {
    Exit,
    Signal,
}
_Process_Handle :: posix.pid_t


_Process :: struct {
    pid:         Process_Handle,
    stdout_pipe: Maybe(Pipe),
    stderr_pipe: Maybe(Pipe),
}

_process_handle :: proc(self: Process) -> Process_Handle {
    return self.pid
}

_process_wait :: proc(
    self: Process,
    alloc: Alloc,
    loc: Loc,
) -> (
    result: Process_Result,
    log: Maybe(string),
    err: Error,
) {
    for {
        status: i32
        child_pid := posix.waitpid(self.pid, &status, {})
        if child_pid == FAIL {
            err = Process_Cannot_Exit{child_pid, posix.errno()}
        }
        result.duration = time.since(self.execution_time)

        current: ^Process_Status
        child_appended: bool
        if g_process_tracker_initialised {
            if sync.mutex_guard(g_process_tracker_mutex) {
                if len(g_process_tracker^) <= 0 {
                    child_appended = false
                } else {
                    current = g_process_tracker[self.pid]
                    child_appended = true
                }
            }
        }

        defer if g_process_tracker_initialised {
            if sync.mutex_guard(g_process_tracker_mutex) {
                delete_key(g_process_tracker, self.pid)
            }
        }

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
                pipe_close_read(&stdout_pipe, loc) or_return
                pipe_close_read(&stderr_pipe, loc) or_return
            }

            if g_process_tracker_initialised {
                if !(child_appended && sync.atomic_load(&current.has_run)) {     // short-circuit evaluation
                    err = Process_Not_Executed{self.pid}
                }
                if child_appended {
                    if sync.mutex_guard(g_process_tracker_mutex) {
                        log = strings.to_string(current.log)
                        if len(log.?) <= 0 {
                            log = nil
                        }
                    }
                }
            }
        }

        if posix.WIFEXITED(status) {
            exit_code := posix.WEXITSTATUS(status)
            result.exit = (exit_code == 0) ? nil : Exit(exit_code)
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
    stdout_pipe, stderr_pipe: Pipe
    dev_null: posix.FD
    if option == .Capture || option == .Silent {
        dev_null = posix.open("/dev/null", {.RDWR, .CREAT}, {.IWUSR, .IWGRP, .IWOTH})
        assert(posix.errno() == .NONE, "could not open /dev/null")
    }
    if option == .Capture {
        pipe_init(&stdout_pipe, loc) or_return
        pipe_init(&stderr_pipe, loc) or_return
    }

    argv := make([dynamic]cstring, 0, len(args) + 3)
    append(&argv, "/usr/bin/env")
    append(&argv, fmt.ctprint(prog))
    for arg in args {
        append(&argv, fmt.ctprintf("%s", arg))
    }
    append(&argv, nil)

    if g_flags & {.Echo_Commands, .Echo_Commands_Debug} != {} {
        msg := fmt.tprintf(
            "(%v) %s %s",
            option,
            prog,
            concat_string_sep(args, " ", context.temp_allocator),
        )
        if .Echo_Commands in g_flags {
            log_info(msg, loc = loc)
        } else if .Echo_Commands_Debug in g_flags {
            log_debug(msg, loc = loc)
        }
    }

    child_pid := posix.fork()
    if child_pid == FAIL {
        err = Spawn_Failed{posix.errno()}
        return
    }

    if child_pid == 0 {
        fail :: proc() {
            posix.exit(1)
        }

        pid := posix.getpid()
        current: ^Process_Status
        logger: log.Logger
        if g_process_tracker_initialised {
            status := new(Process_Status, g_shared_mem_allocator)
            _, builder_err := strings.builder_init_len_cap(
                &status.log,
                0,
                1024,
                g_shared_mem_allocator,
            )
            assert(builder_err == .None)
            if sync.mutex_guard(g_process_tracker_mutex) {
                assert(g_process_tracker != nil || g_process_tracker_mutex != nil)
                current = map_insert(g_process_tracker, pid, status)^
                logger = create_process_logger(
                    &current.log,
                    g_shared_mem_allocator,
                    g_process_tracker_mutex,
                )
            }
        } else {
            logger = log.Logger {
                proc(_: rawptr, _: log.Level, _: string, _: log.Options, _: Loc) {},
                nil,
                log.Level.Debug,
                {},
            }
        }
        context.logger = logger
        enable_default_flags({.Use_Context_Logger})

        // TODO: how to handle errors the new way here?
        switch option {
        case .Share:
            break
        case .Silent:
            if fd_redirect(dev_null, posix.STDOUT_FILENO, loc) != nil {fail()}
            if fd_redirect(dev_null, posix.STDERR_FILENO, loc) != nil {fail()}
            if fd_redirect(dev_null, posix.STDIN_FILENO, loc) != nil {fail()}
            if fd_close(dev_null, loc) != nil {fail()}
        case .Capture:
            if pipe_close_read(&stdout_pipe, loc) != nil {fail()}
            if pipe_close_read(&stderr_pipe, loc) != nil {fail()}

            if pipe_redirect(&stdout_pipe, posix.STDOUT_FILENO, loc) != nil {fail()}
            if pipe_redirect(&stderr_pipe, posix.STDERR_FILENO, loc) != nil {fail()}
            if fd_redirect(dev_null, posix.STDIN_FILENO, loc) != nil {fail()}

            if pipe_close_write(&stdout_pipe, loc) != nil {fail()}
            if pipe_close_write(&stderr_pipe, loc) != nil {fail()}
            if fd_close(dev_null, loc) != nil {fail()}
        }

        if g_process_tracker_initialised {
            _, exch_ok := sync.atomic_compare_exchange_strong(&current.has_run, false, true)
            assert(exch_ok)
        }
        if posix.execve(argv[0], raw_data(argv), posix.environ) == FAIL {
            if g_process_tracker_initialised {
                _, exch_ok := sync.atomic_compare_exchange_strong(&current.has_run, true, false)
                assert(exch_ok)
            }
            log_errorf("Failed to run `%s`: %s", prog, posix.strerror(posix.errno()), loc = loc)
            fail()
        }
        unreachable()
    }
    execution_time := time.now()

    if option == .Capture || option == .Silent {
        fd_close(dev_null, loc) or_return
    }

    delete(argv, loc = loc)
    maybe_stdout_pipe: Maybe(Pipe) = (option == .Capture) ? stdout_pipe : nil
    maybe_stderr_pipe: Maybe(Pipe) = (option == .Capture) ? stderr_pipe : nil
    return {
            pid = child_pid,
            execution_time = execution_time,
            stdout_pipe = maybe_stdout_pipe,
            stderr_pipe = maybe_stderr_pipe,
        },
        err
}


_Process_Tracker_Error :: union {
    Mmap_Failed,
    Unmap_Failed,
    Arena_Init_Failed,
}

Mmap_Failed :: struct {
    errno: Errno,
}

Unmap_Failed :: struct {
    errno: Errno,
}

Arena_Init_Failed :: struct {
    err: mem.Allocator_Error,
}

process_tracker_strerror :: proc(
    err: _Process_Tracker_Error,
    alloc := context.allocator,
) -> string {
    context.allocator = alloc
    switch v in err {
    case Mmap_Failed:
        return fmt.aprintf("Failed to map shared memory: %s", strerrno(v.errno))
    case Unmap_Failed:
        return fmt.aprintf("Failed to unmap shared memory: %s", strerrno(v.errno))
    case Arena_Init_Failed:
        return fmt.aprintf("Failed to initialise arena from shared memory: %v", v.err)
    }
    unreachable()
}

// DOCS: do not manually call `_process_tracker_init`
_process_tracker_init :: proc() -> (err: Process_Tracker_Error) {
    g_shared_mem = posix.mmap(
        rawptr(uintptr(0)),
        SHARED_MEM_SIZE,
        {.READ, .WRITE},
        {.SHARED, .ANONYMOUS},
    )
    if g_shared_mem == posix.MAP_FAILED {
        return Mmap_Failed{posix.errno()}
    }

    arena_err := virtual.arena_init_buffer(
        &g_shared_mem_arena,
        slice.bytes_from_ptr(g_shared_mem, SHARED_MEM_SIZE),
    )
    if arena_err != .None {
        return Arena_Init_Failed{arena_err}
    }
    context.allocator = virtual.arena_allocator(&g_shared_mem_arena)
    g_shared_mem_allocator = context.allocator

    g_process_tracker = new(Process_Tracker)
    _ = reserve(g_process_tracker, 128)

    // yep
    process_tracker_mutex := sync.Mutex{}
    process_tracker_mutex_rawptr, _ := mem.alloc(size_of(sync.Mutex))
    g_process_tracker_mutex =
    cast(^sync.Mutex)libc.memmove(
        process_tracker_mutex_rawptr,
        &process_tracker_mutex,
        size_of(sync.Mutex),
    )

    return nil
}

// DOCS: do not manually call `_process_tracker_destroy`
_process_tracker_destroy :: proc() -> (err: Process_Tracker_Error) {
    if g_shared_mem != nil {
        if posix.munmap(g_shared_mem, SHARED_MEM_SIZE) == .FAIL {
            return Unmap_Failed{posix.errno()}
        }
    }
    return nil
}


_program :: proc($name: string, loc: Loc) -> (found: bool) {
    res, err := run_prog_sync_unchecked(
        "sh",
        {"-c", "command -v " + name},
        .Silent,
        context.temp_allocator,
        loc,
    )
    return res.exit == nil && err == nil
}


_Internal_Error :: union {
    // `pipe_init`
    Fd_Create_Failed,
    // `pipe_close_*`, `fd_close`
    Fd_Close_Failed,
    // `pipe_redirect`, `fd_redirect`
    Fd_Redirect_Failed,
    // `pipe_reaa`
    Pipe_Read_Failed,
}

Fd_Kind :: enum {
    File,
    Pipe,
    Read_Pipe,
    Write_Pipe,
}

Fd_Create_Failed :: struct {
    errno: Errno,
    kind:  Fd_Kind,
}

Fd_Close_Failed :: struct {
    errno: Errno,
    kind:  Fd_Kind,
}

Fd_Redirect_Failed :: struct {
    errno: Errno,
    kind:  Fd_Kind,
    oldfd: posix.FD,
    newfd: posix.FD,
}

Pipe_Read_Failed :: struct {
    errno: Errno,
}

internal_strerror :: proc(err: Internal_Error, alloc := context.allocator) -> string {
    context.allocator = alloc
    switch v in err {
    case Fd_Create_Failed:
        kind_str: string
        switch v.kind {
        case .Pipe, .Read_Pipe, .Write_Pipe:
            kind_str = "pipes"
        case .File:
            kind_str = "file"
        }
        return fmt.aprintf("Failed to create %s: %s", kind_str, strerrno(v.errno))
    case Fd_Close_Failed:
        kind_str: string
        switch v.kind {
        case .Pipe:
            kind_str = "pipe"
        case .Read_Pipe:
            kind_str = "read pipe"
        case .Write_Pipe:
            kind_str = "write pipe"
        case .File:
            kind_str = "file"
        }
        return fmt.aprintf("Failed to close %s: %s", kind_str, strerrno(v.errno))
    case Fd_Redirect_Failed:
        kind_str: string
        switch v.kind {
        case .Pipe, .Read_Pipe, .Write_Pipe:
            kind_str = "pipe"
        case .File:
            kind_str = "file"
        }
        return fmt.aprintf(
            "Failed to redirect old %s: %v, new %s: %v: %s",
            kind_str,
            v.oldfd,
            kind_str,
            v.newfd,
            strerrno(v.errno),
        )
    case Pipe_Read_Failed:
        return fmt.aprintf("Failed to read pipe: %s", strerrno(v.errno))
    }
    unreachable()
}


Pipe :: struct #raw_union {
    array: Pipe_Both,
    struc: Pipe_Separate,
}
Pipe_Both :: [2]posix.FD
Pipe_Separate :: struct #align (size_of(posix.FD)) {
    read:  posix.FD,
    write: posix.FD,
}

@(require_results)
pipe_init :: proc(self: ^Pipe, loc: Loc) -> (err: Internal_Error) {
    if posix.pipe(&self.array) == .FAIL {
        return Fd_Create_Failed{posix.errno(), .Pipe}
    }
    return nil
}

@(require_results)
pipe_close_read :: proc(self: ^Pipe, loc: Loc) -> (err: Internal_Error) {
    if posix.close(self.struc.read) == .FAIL {
        return Fd_Close_Failed{posix.errno(), .Read_Pipe}
    }
    return nil
}

@(require_results)
pipe_close_write :: proc(self: ^Pipe, loc: Loc) -> (err: Internal_Error) {
    if posix.close(self.struc.write) == .FAIL {
        return Fd_Close_Failed{posix.errno(), .Write_Pipe}
    }
    return nil
}

@(require_results)
pipe_redirect :: proc(self: ^Pipe, newfd: posix.FD, loc: Loc) -> (err: Internal_Error) {
    if posix.dup2(self.struc.write, newfd) == FAIL {
        return Fd_Redirect_Failed{posix.errno(), .Pipe, self.struc.write, newfd}
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
    err: Internal_Error,
) {
    INITIAL_BUF_SIZE :: 1024
    pipe_close_write(self, loc) or_return
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
            err = Pipe_Read_Failed{posix.errno()}
            return
        }
        total_bytes_read += bytes_read
        if total_bytes_read >= len(buf) {
            resize(&buf, 2 * len(buf))
        }
    }
    result = strings.clone_from_bytes(buf[:total_bytes_read], alloc)
    return
}


@(require_results)
fd_redirect :: proc(fd: posix.FD, newfd: posix.FD, loc: Loc) -> (err: Internal_Error) {
    if posix.dup2(fd, newfd) == FAIL {
        return Fd_Redirect_Failed{posix.errno(), .File, fd, newfd}
    }
    return nil
}

@(require_results)
fd_close :: proc(fd: posix.FD, loc: Loc) -> (err: Internal_Error) {
    if posix.close(fd) == .FAIL {
        return Fd_Close_Failed{posix.errno(), .File}
    }
    return nil
}

strerrno :: proc(errno: Errno) -> string {
    return string(posix.strerror(errno))
}

