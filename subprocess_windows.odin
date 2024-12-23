#+build windows
#+private
package subprocess

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import fpath "core:path/filepath"
import "core:strings"
import win "core:sys/windows"
import "core:time"


_Process_Exit :: win.DWORD
_Process_Handle :: struct {
    process: win.HANDLE,
    thread:  win.HANDLE,
}

_is_success :: proc(exit: Process_Exit) -> bool {
    return exit == 0
}


_process_wait :: proc(self: ^Process, alloc: Alloc, loc: Loc) -> (result: Result, err: Error) {
    defer if err != nil {
        result_destroy(&result, alloc)
    }

    process_wait_assert(self)

    stdout_pipe, stdout_pipe_ok := &self.stdout_pipe.?
    stderr_pipe, stderr_pipe_ok := &self.stderr_pipe.?
    stdin_pipe, stdin_pipe_ok := &self.stdin_pipe.?
    stdout_buf, stderr_buf: [dynamic]byte
    INITIAL_BUF_CAP :: 1 * mem.Kilobyte
    if stdout_pipe_ok {
        stdout_buf = make([dynamic]byte, 0, INITIAL_BUF_CAP, alloc)
    }
    if stderr_pipe_ok {
        stderr_buf = make([dynamic]byte, 0, INITIAL_BUF_CAP, alloc)
    }
    defer if err != nil && stdout_pipe_ok {
        delete(stdout_buf)
    }
    defer if err != nil && stderr_pipe_ok {
        delete(stderr_buf)
    }

    for {
        bytes_read: uint
        if stdout_pipe_ok {
            bytes_read += _pipe_read(stdout_pipe, &stdout_buf, loc) or_return
        }
        if stderr_pipe_ok {
            bytes_read += _pipe_read(stderr_pipe, &stderr_buf, loc) or_return
        }
        if bytes_read == 0 {
            break
        }
    }

    if res := win.WaitForSingleObject(self.handle.process, win.INFINITE);
       res == win.WAIT_OBJECT_0 {
        result.duration = time.since(self.execution_time)
        self.alive = false
    } else if res == win.WAIT_TIMEOUT {
        unreachable()
    } else {
        err = General_Error.Process_Cannot_Exit
        return
    }

    if !win.GetExitCodeProcess(self.handle.process, &result.exit) {
        err = General_Error.Process_Cannot_Exit
        return
    }

    if stdout_pipe_ok {
        pipe_ensure_closed(stdout_pipe) or_return
        result.stdout = stdout_buf[:]
    }
    if stderr_pipe_ok {
        pipe_ensure_closed(stderr_pipe) or_return
        result.stderr = stderr_buf[:]
    }
    if stdin_pipe_ok {
        pipe_ensure_closed(stdin_pipe) or_return
    }

    return
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
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    sec_attrs := win.SECURITY_ATTRIBUTES {
        nLength              = size_of(win.SECURITY_ATTRIBUTES),
        lpSecurityDescriptor = nil,
        bInheritHandle       = true,
    }

    start_info: win.STARTUPINFOW
    start_info.cb = size_of(win.STARTUPINFOW)
    stdout_pipe, stderr_pipe, stdin_pipe: _Pipe
    dev_null: win.HANDLE = win.INVALID_HANDLE_VALUE

    switch opts.output {
    case .Share:
        start_info.hStdOutput = win.GetStdHandle(win.STD_OUTPUT_HANDLE)
        start_info.hStdError = win.GetStdHandle(win.STD_ERROR_HANDLE)
    case .Silent:
        open_dev_null(&dev_null, &sec_attrs)
        start_info.hStdOutput = dev_null
        start_info.hStdError = dev_null
    case .Capture:
        pipe_init(&stdout_pipe, &sec_attrs) or_return
        pipe_init(&stderr_pipe, &sec_attrs) or_return
        start_info.hStdOutput = stdout_pipe.write
        start_info.hStdError = stderr_pipe.write
    case .Capture_Combine:
        pipe_init(&stdout_pipe, &sec_attrs) or_return
        start_info.hStdOutput = stdout_pipe.write
        start_info.hStdError = stdout_pipe.write
    }

    switch opts.input {
    case .Share:
        start_info.hStdInput = win.GetStdHandle(win.STD_INPUT_HANDLE)
    case .Nothing:
        open_dev_null(&dev_null, &sec_attrs)
        start_info.hStdInput = dev_null
    case .Pipe:
        pipe_init(&stdin_pipe, &sec_attrs) or_return
        start_info.hStdInput = stdin_pipe.read
    }

    assert(
        start_info.hStdOutput != nil && start_info.hStdError != nil && start_info.hStdInput != nil,
    )
    start_info.dwFlags |= win.STARTF_USESTDHANDLES

    mode: Escaping_Mode = .Win_Cmd if fpath.stem(prog) == "cmd" else .Win_API
    cmd := combine_args(prog, args, mode, context.temp_allocator)
    echo_command(opts, mode, prog, args, loc)

    env: [^]win.WCHAR
    env_cap := -1
    defer if env_cap >= 0 {
        runtime.mem_free_with_size(env, env_cap * size_of(win.WCHAR))
    }
    if !opts.zero_env && len(opts.extra_env) == 0 {
        env = nil
    } else if opts.zero_env && len(opts.extra_env) == 0 {
        env = raw_data([]win.WCHAR{0, 0})
    } else {
        env_arr := make([dynamic]win.WCHAR)
        if !opts.zero_env {
            sysenvs := ([^]win.WCHAR)(win.GetEnvironmentStringsW())
            if sysenvs == nil {
                err = General_Error.Spawn_Failed
                return
            }
            defer win.FreeEnvironmentStringsW(sysenvs)
            for from, i := 0, 0; true; i += 1 {
                if c := sysenvs[i]; c == 0 {
                    if i <= from {
                        break
                    }
                    for char in sysenvs[from:i] {
                        append(&env_arr, char)
                    }
                    append(&env_arr, 0)
                    from = i + 1
                }
            }
        }
        for x in opts.extra_env {
            wstr := win.utf8_to_wstring(x)
            for i := 0; wstr[i] != 0; i += 1 {
                append(&env_arr, wstr[i])
            }
            append(&env_arr, 0)
        }
        append(&env_arr, 0)
        env = raw_data(env_arr)
        env_cap = cap(env_arr)
    }

    proc_info: win.PROCESS_INFORMATION
    ok := win.CreateProcessW(
        nil,
        win.utf8_to_wstring(cmd),
        nil,
        nil,
        true,
        win.CREATE_UNICODE_ENVIRONMENT,
        env,
        nil,
        &start_info,
        &proc_info,
    )

    close_dev_null(&dev_null)

    switch opts.output {
    case .Share, .Silent:
        break
    case .Capture:
        pipe_close_write(&stdout_pipe) or_return
        pipe_close_write(&stderr_pipe) or_return
    case .Capture_Combine:
        pipe_close_write(&stdout_pipe) or_return
    }

    if opts.input == .Pipe {
        pipe_close_read(&stdin_pipe) or_return
    }

    if ok {
        process.execution_time = time.now()
        process.alive = true

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

        process.opts = opts
        process.handle = {proc_info.hProcess, proc_info.hThread}
    } else {
        switch opts.output {
        case .Share, .Silent:
            break
        case .Capture:
            pipe_close_read(&stdout_pipe) or_return
            pipe_close_read(&stderr_pipe) or_return
        case .Capture_Combine:
            pipe_close_read(&stdout_pipe) or_return
        }
        if opts.input == .Pipe {
            pipe_close_write(&stdin_pipe) or_return
        }
        err = General_Error.Spawn_Failed
    }

    return
}


_program :: proc(name: string, alloc: Alloc, loc: Loc) -> (path: string, err: Error) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(alloc == context.temp_allocator)
    res: Result
    res = exec(
        "cmd",
        {"/C", fmt.tprint("where", name, "&& exit 0 || exit 1")},
        {output = .Capture, dont_echo_command = true},
        alloc = context.temp_allocator,
    ) or_return

    if !result_success(res) {
        if ext := fpath.ext(strings.to_lower(name, context.temp_allocator)); os.exists(name) {
            switch ext {
            case ".exe", ".com", ".bat", ".cmd":
                path = strings.clone(name, alloc, loc)
                return
            }
        }
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
    // Failed to read from the pipe
    Pipe_Read_Failed,
    // Failed to close the file handle
    Handle_Close_Failed,
}


_Pipe :: struct {
    read:  win.HANDLE,
    write: win.HANDLE,
}

@(require_results)
pipe_init :: proc(self: ^Pipe, sec_attrs: ^win.SECURITY_ATTRIBUTES) -> (err: Error) {
    // NOTE: SetHandleInformation to read end for OUT pipe or to write end for IN pipe
    if !win.CreatePipe(&self.read, &self.write, sec_attrs, 0) &&
       !win.SetHandleInformation(self.read, win.HANDLE_FLAG_INHERIT, 0) {
        return Internal_Error.Pipe_Init_Failed
    }
    return nil
}

@(require_results)
pipe_close_read :: proc(self: ^Pipe) -> (err: Error) {
    if self.read == win.INVALID_HANDLE_VALUE {return}
    if !win.CloseHandle(self.read) {
        return Internal_Error.Pipe_Close_Failed
    }
    self.read = win.INVALID_HANDLE_VALUE
    return nil
}

@(require_results)
pipe_close_write :: proc(self: ^Pipe) -> (err: Error) {
    if self.write == win.INVALID_HANDLE_VALUE {return}
    if !win.CloseHandle(self.write) {
        return Internal_Error.Pipe_Close_Failed
    }
    self.write = win.INVALID_HANDLE_VALUE
    return nil
}

@(require_results)
pipe_ensure_closed :: proc(self: ^Pipe) -> (err: Error) {
    pipe_close_read(self) or_return
    pipe_close_write(self) or_return
    self^ = {}
    return nil
}

@(require_results)
_pipe_read :: proc(self: ^Pipe, buf: ^[dynamic]byte, loc: Loc) -> (bytes_read: uint, err: Error) {
    if self.read == win.INVALID_HANDLE_VALUE {return}
    init_len: uint = len(buf)
    defer if err != nil {
        resize(buf, init_len)
    }
    for (_pipe_read_once(self, buf, loc) or_return) != 0 {}
    assert(init_len <= len(buf))
    return len(buf) - init_len, nil
}

@(require_results)
_pipe_read_once :: proc(
    self: ^Pipe,
    buf: ^[dynamic]byte,
    loc: Loc,
) -> (
    bytes_read: uint,
    err: Error,
) {
    if self.read == win.INVALID_HANDLE_VALUE {return}
    dword_bytes_read: win.DWORD
    slice := raw_data(buf^)[len(buf):]
    ok := win.ReadFile(self.read, slice, win.DWORD(cap(buf) - len(buf)), &dword_bytes_read, nil)
    if dword_bytes_read == 0 {
        return
    } else if !ok {
        err = Internal_Error.Pipe_Read_Failed
        return
    }
    bytes_read = uint(dword_bytes_read)
    non_zero_resize(buf, len(buf) + int(bytes_read))
    if len(buf) >= cap(buf) {
        reserve(buf, 2 * cap(buf))
    }
    return
}

@(require_results)
_pipe_write_buf :: proc(self: Pipe, buf: []byte) -> (n: int, err: Error) {
    if self.write == win.INVALID_HANDLE_VALUE {return}
    written: win.DWORD
    if !win.WriteFile(self.write, raw_data(buf), win.DWORD(len(buf)), &written, nil) {
        err = General_Error.Pipe_Write_Failed
        return
    } else {
        return int(written), nil
    }
}

@(require_results)
_pipe_write_string :: proc(self: Pipe, str: string) -> (n: int, err: Error) {
    if self.write == win.INVALID_HANDLE_VALUE {return}
    written: win.DWORD
    if !win.WriteFile(self.write, raw_data(str), win.DWORD(len(str)), &written, nil) {
        err = General_Error.Pipe_Write_Failed
        return
    } else {
        return int(written), nil
    }
}


@(require_results)
handle_close :: proc(handle: ^win.HANDLE) -> (err: Error) {
    if handle^ == win.INVALID_HANDLE_VALUE {return}
    if !win.CloseHandle(handle^) {
        return Internal_Error.Handle_Close_Failed
    }
    handle^ = win.INVALID_HANDLE_VALUE
    return nil
}

open_dev_null :: proc(handle: ^win.HANDLE, sec_attrs: ^win.SECURITY_ATTRIBUTES) {
    if handle == nil || handle^ == win.INVALID_HANDLE_VALUE {
        handle^ = win.CreateFileW(
            win.utf8_to_wstring("NUL"),
            win.GENERIC_WRITE | win.GENERIC_READ,
            win.FILE_SHARE_WRITE | win.FILE_SHARE_READ,
            sec_attrs,
            win.OPEN_EXISTING,
            win.FILE_ATTRIBUTE_NORMAL,
            nil,
        )
        assert(handle^ != win.INVALID_HANDLE_VALUE, "could not open NUL device")
    }
}

close_dev_null :: proc(handle: ^win.HANDLE) {
    if handle^ == win.INVALID_HANDLE_VALUE {return}
    assert(handle_close(handle) == nil, "could not close NUL device")
    handle^ = win.INVALID_HANDLE_VALUE
}

