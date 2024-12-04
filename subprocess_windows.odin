#+build windows
#+private
package subprocess

import "base:runtime"
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

    if res := win.WaitForSingleObject(self.handle.process, win.INFINITE);
       res == win.WAIT_OBJECT_0 {
        result.duration = time.since(self.execution_time)
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

    stdout_pipe, stdout_pipe_ok := self.stdout_pipe.?
    stderr_pipe, stderr_pipe_ok := self.stderr_pipe.?
    stdin_pipe, stdin_pipe_ok := self.stdin_pipe.?
    if stdout_pipe_ok {
        result.stdout = pipe_read(&stdout_pipe, loc, alloc) or_return
        pipe_close_read(stdout_pipe) or_return
    }
    if stderr_pipe_ok {
        result.stderr = pipe_read(&stderr_pipe, loc, alloc) or_return
        pipe_close_read(stderr_pipe) or_return
    }
    if stdin_pipe_ok {
        pipe_close_write(stdin_pipe) or_return
    }

    return
}


_run_prog_async_unchecked :: proc(
    prog: string,
    args: []string,
    out_opt: Output_Option = .Share,
    in_opt: Input_Option = .Share,
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
    dev_null: win.HANDLE

    switch out_opt {
    case .Share:
        start_info.hStdOutput = win.GetStdHandle(win.STD_OUTPUT_HANDLE)
        start_info.hStdError = win.GetStdHandle(win.STD_ERROR_HANDLE)
    case .Silent:
        dev_null = win.CreateFileW(
            win.utf8_to_wstring("NUL"),
            win.GENERIC_WRITE | win.GENERIC_READ,
            win.FILE_SHARE_WRITE | win.FILE_SHARE_READ,
            &sec_attrs,
            win.OPEN_EXISTING,
            win.FILE_ATTRIBUTE_NORMAL,
            nil,
        )
        assert(dev_null != win.INVALID_HANDLE_VALUE, "could not open NUL device")
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

    switch in_opt {
    case .Share:
        start_info.hStdInput = win.GetStdHandle(win.STD_INPUT_HANDLE)
    case .Nothing:
        if dev_null == nil {
            dev_null = win.CreateFileW(
                win.utf8_to_wstring("NUL"),
                win.GENERIC_WRITE | win.GENERIC_READ,
                win.FILE_SHARE_WRITE | win.FILE_SHARE_READ,
                &sec_attrs,
                win.OPEN_EXISTING,
                win.FILE_ATTRIBUTE_NORMAL,
                nil,
                )
            assert(dev_null != win.INVALID_HANDLE_VALUE, "could not open NUL device")
        }
        start_info.hStdInput = dev_null
    case .Pipe:
        pipe_init(&stdin_pipe, &sec_attrs) or_return
        start_info.hStdInput = stdin_pipe.read
    }

    assert(start_info.hStdOutput != nil && start_info.hStdError != nil && start_info.hStdInput != nil)
    start_info.dwFlags |= win.STARTF_USESTDHANDLES

    cmd := combine_args(prog, args, context.temp_allocator)
    print_cmd(out_opt, in_opt, prog, args, loc)

    proc_info: win.PROCESS_INFORMATION
    // NOTE: Environment variables of the calling process are passed
    ok := win.CreateProcessW(
        nil,
        win.utf8_to_wstring(cmd),
        nil,
        nil,
        true,
        0,
        nil,
        nil,
        &start_info,
        &proc_info,
    )

    if out_opt == .Silent || in_opt == .Nothing {
        handle_close(dev_null) or_return
    }

    switch out_opt {
    case .Share, .Silent:
        break
    case .Capture:
        pipe_close_write(stdout_pipe) or_return
        pipe_close_write(stderr_pipe) or_return
    case .Capture_Combine:
        pipe_close_write(stdout_pipe) or_return
    }

    if in_opt == .Pipe {
        pipe_close_read(stdin_pipe) or_return
    }

    if ok {
        process.execution_time = time.now()
        process.alive = true

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

        process.handle = {proc_info.hProcess, proc_info.hThread}
    } else {
        switch out_opt {
        case .Share, .Silent:
            break
        case .Capture:
            pipe_close_read(stdout_pipe) or_return
            pipe_close_read(stderr_pipe) or_return
        case .Capture_Combine:
            pipe_close_read(stdout_pipe) or_return
        }
        if in_opt == .Pipe {
            pipe_close_write(stdin_pipe) or_return
        }
        err = General_Error.Spawn_Failed
    }

    return
}


_program :: proc($name: string, loc: Loc) -> (found: bool) {
    res, err := run_prog_sync_unchecked(
        "cmd",
        {"/C where " + name + " && exit 0 || exit 1"},
        .Silent,
        .Share,
        context.temp_allocator,
        loc,
    )
    return process_result_success(res) && err == nil
}


_Internal_Error :: enum u8 {
    None = 0,
    Pipe_Init_Failed,
    Pipe_Close_Failed,
    Pipe_Read_Failed,
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
pipe_close_read :: proc(self: Pipe) -> (err: Error) {
    return nil if win.CloseHandle(self.read) else Internal_Error.Pipe_Close_Failed
}

@(require_results)
pipe_close_write :: proc(self: Pipe) -> (err: Error) {
    return nil if win.CloseHandle(self.write) else Internal_Error.Pipe_Close_Failed
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
    total_bytes_read: win.DWORD
    buf := make([dynamic]byte, INITIAL_BUF_SIZE)
    defer delete(buf)
    for {
        bytes_read: win.DWORD
        ok := win.ReadFile(
            self.read,
            raw_data(buf[total_bytes_read:]),
            win.DWORD(len(buf[total_bytes_read:])),
            &bytes_read,
            nil,
        )
        if bytes_read == 0 {
            break
        } else if !ok {
            err = Internal_Error.Pipe_Read_Failed
            return
        }
        total_bytes_read += bytes_read
        if total_bytes_read >= win.DWORD(len(buf)) {
            resize(&buf, 2 * len(buf))
        }
    }
    result = strings.clone_from_bytes(buf[:total_bytes_read], alloc, loc)
    return
}

@(require_results)
_pipe_write_buf :: proc(self: Pipe, buf: []byte) -> (n: int, err: Error) {
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
    written: win.DWORD
    if !win.WriteFile(self.write, raw_data(str), win.DWORD(len(str)), &written, nil) {
        err = General_Error.Pipe_Write_Failed
        return
    } else {
        return int(written), nil
    }
}


@(require_results)
handle_close :: proc(handle: win.HANDLE) -> Error {
    return nil if win.CloseHandle(handle) else Internal_Error.Handle_Close_Failed
}

