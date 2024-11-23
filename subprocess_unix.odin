#+build linux, darwin, netbsd, openbsd, freebsd
package subprocess

import "core:c/libc"
import "core:encoding/ansi"
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
    ok: bool,
) {
    for {
        status: i32
        early_exit: bool
        child_pid := posix.waitpid(self.pid, &status, {})
        if child_pid == FAIL {
            log_errorf("Process %v cannot exit: %s", child_pid, strerror(), loc = loc)
            early_exit = true
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
                log_str: Maybe(string)
                if !(child_appended && sync.atomic_load(&current.has_run)) {     // short-circuit evaluation
                    early_exit = true
                    log_errorf(
                        "Process %v did not execute the command successfully",
                        self.pid,
                        loc = loc,
                    )
                }
                if child_appended {
                    if sync.mutex_guard(g_process_tracker_mutex) {
                        log_str = strings.to_string(current.log)
                        if len(log_str.?) <= 0 {
                            log_str = nil
                        }
                    }
                }
                if log_str != nil {
                    log_infof(
                        strings.concatenate(
                            {
                                "Log from %v:\n",
                                ansi_graphic(ansi.BG_BRIGHT_BLACK, alloc = context.temp_allocator),
                                "%s",
                                ansi_reset(),
                            },
                            context.temp_allocator,
                        ),
                        self.pid,
                        log_str.?,
                        loc = loc,
                    )
                }
            }
        }

        if posix.WIFEXITED(status) {
            exit_code := posix.WEXITSTATUS(status)
            result.exit = (exit_code == 0) ? nil : Exit(exit_code)
            ok = true && !early_exit
            return
        }

        if posix.WIFSIGNALED(status) {
            result.exit = Signal(posix.WTERMSIG(status))
            ok = true && !early_exit
            return
        }
    }
}

_process_wait_many :: proc(
    selves: []Process,
    alloc: Alloc,
    loc: Loc,
) -> (
    results: []Process_Result,
    ok: bool,
) {
    ok = true
    defer if !ok {
        results = nil
    }
    results = make([]Process_Result, len(selves), alloc, loc)
    for process, i in selves {
        process_result, process_ok := process_wait(process, alloc, loc)
        ok &&= process_ok
        results[i] = process_result
    }
    return
}


_process_result_destroy :: proc(self: ^Process_Result, loc: Loc) {
    delete(self.stdout, loc = loc)
    delete(self.stderr, loc = loc)
    self^ = {}
}

_process_result_destroy_many :: proc(selves: []Process_Result, loc: Loc) {
    for &result in selves {
        process_result_destroy(&result, loc)
    }
}


_run_prog_async_unchecked :: proc(
    prog: string,
    args: []string,
    option: Run_Prog_Option = .Share,
    loc: Loc,
) -> (
    process: Process,
    ok: bool,
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

    if .Echo_Commands in g_flags {
        log_debugf(
            "(%v) %s %s",
            option,
            prog,
            concat_string_sep(args, " ", context.temp_allocator),
            loc = loc,
        )
    }

    child_pid := posix.fork()
    if child_pid == FAIL {
        log_errorf("Failed to fork child process: %s", strerror(), loc = loc)
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
                logger = create_builder_logger(
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

        switch option {
        case .Share:
            break
        case .Silent:
            if !fd_redirect(dev_null, posix.STDOUT_FILENO, loc) {fail()}
            if !fd_redirect(dev_null, posix.STDERR_FILENO, loc) {fail()}
            if !fd_redirect(dev_null, posix.STDIN_FILENO, loc) {fail()}
            if !fd_close(dev_null, loc) {fail()}
        case .Capture:
            if !pipe_close_read(&stdout_pipe, loc) {fail()}
            if !pipe_close_read(&stderr_pipe, loc) {fail()}

            if !pipe_redirect(&stdout_pipe, posix.STDOUT_FILENO, loc) {fail()}
            if !pipe_redirect(&stderr_pipe, posix.STDERR_FILENO, loc) {fail()}
            if !fd_redirect(dev_null, posix.STDIN_FILENO, loc) {fail()}

            if !pipe_close_write(&stdout_pipe, loc) {fail()}
            if !pipe_close_write(&stderr_pipe, loc) {fail()}
            if !fd_close(dev_null, loc) {fail()}
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
            log_errorf("Failed to run `%s`: %s", prog, strerror(), loc = loc)
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
        true
}


// DOCS: do not manually call `_process_tracker_init`
_process_tracker_init :: proc() -> (ok: bool) {
    g_shared_mem = posix.mmap(
        rawptr(uintptr(0)),
        SHARED_MEM_SIZE,
        {.READ, .WRITE},
        {.SHARED, .ANONYMOUS},
    )
    if g_shared_mem == posix.MAP_FAILED {
        log_errorf("Failed to map shared memory: %s", strerror())
        return
    }

    arena_err := virtual.arena_init_buffer(
        &g_shared_mem_arena,
        slice.bytes_from_ptr(g_shared_mem, SHARED_MEM_SIZE),
    )
    if arena_err != .None {
        log_errorf("Failed to initialized arena from shared memory: %v", arena_err)
        return
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

    return true
}

// DOCS: do not manually call `_process_tracker_destroy`
_process_tracker_destroy :: proc() -> (ok: bool) {
    if g_shared_mem != nil {
        if posix.munmap(g_shared_mem, SHARED_MEM_SIZE) == .FAIL {
            log_errorf("Failed to unmap shared memory: %s", strerror())
            return
        }
    }
    return true
}


_program :: proc($name: string, loc: Loc) -> (found: bool) {
    res, ok := run_prog_sync_unchecked(
        "sh",
        {"-c", "command -v " + name},
        .Silent,
        context.temp_allocator,
        loc,
    )
    return res.exit == nil && ok
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
pipe_init :: proc(self: ^Pipe, loc: Loc) -> (ok: bool) {
    if posix.pipe(&self.array) == .FAIL {
        log_errorf("Failed to create pipes: %s", strerror(), loc = loc)
        return false
    }
    return true
}

@(require_results)
pipe_close_read :: proc(self: ^Pipe, loc: Loc) -> (ok: bool) {
    if posix.close(self.struc.read) == .FAIL {
        log_errorf("Failed to close read pipe: %s", strerror(), loc = loc)
        return false
    }
    return true
}

@(require_results)
pipe_close_write :: proc(self: ^Pipe, loc: Loc) -> (ok: bool) {
    if posix.close(self.struc.write) == .FAIL {
        log_errorf("Failed to close write pipe: %s", strerror(), loc = loc)
        return false
    }
    return true
}

@(require_results)
pipe_redirect :: proc(self: ^Pipe, newfd: posix.FD, loc: Loc) -> (ok: bool) {
    if posix.dup2(self.struc.write, newfd) == FAIL {
        log_errorf(
            "Failed to redirect oldfd: %v, newfd: %v: %s",
            self.struc.write,
            newfd,
            strerror(),
            loc = loc,
        )
        return false
    }
    return true
}

@(require_results)
pipe_read :: proc(
    self: ^Pipe,
    loc: Loc,
    alloc := context.allocator,
) -> (
    result: string,
    ok: bool,
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
            log_errorf("Failed to read pipe: %s", strerror(), loc = loc)
            return
        }
        total_bytes_read += bytes_read
        if total_bytes_read >= len(buf) {
            resize(&buf, 2 * len(buf))
        }
    }
    result = strings.clone_from_bytes(buf[:total_bytes_read], alloc)
    ok = true
    return
}


@(require_results)
fd_redirect :: proc(fd: posix.FD, newfd: posix.FD, loc: Loc) -> (ok: bool) {
    if posix.dup2(fd, newfd) == FAIL {
        log_errorf("Failed to redirect oldfd: %v, newfd: %v: %s", fd, newfd, strerror(), loc = loc)
        return false
    }
    return true
}

@(require_results)
fd_close :: proc(fd: posix.FD, loc: Loc) -> (ok: bool) {
    if posix.close(fd) == .FAIL {
        log_errorf("Failed to close fd %v: %s", fd, strerror(), loc = loc)
        return false
    }
    return true
}


strerror :: proc() -> cstring {
    return posix.strerror(posix.errno())
}

