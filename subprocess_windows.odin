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
    if stdout_pipe_ok || stderr_pipe_ok {
        assert(
            stderr_pipe_ok == stdout_pipe_ok,
            "stdout and stderr pipe aren't equally initialized",
        )
        result.stdout = pipe_read(&stdout_pipe, loc, alloc) or_return
        result.stderr = pipe_read(&stderr_pipe, loc, alloc) or_return
        pipe_close_read(stdout_pipe) or_return
        pipe_close_read(stderr_pipe) or_return
    }

    return
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
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    sec_attrs := win.SECURITY_ATTRIBUTES {
        nLength              = size_of(win.SECURITY_ATTRIBUTES),
        lpSecurityDescriptor = nil,
        bInheritHandle       = true,
    }

    start_info: win.STARTUPINFOW
    start_info.cb = size_of(win.STARTUPINFOW)
    stdout_pipe, stderr_pipe: _Pipe
    dev_null: win.HANDLE

    if option == .Silent {
        dev_null = win.CreateFileW(
            win.utf8_to_wstring("NUL"),
            win.GENERIC_WRITE,
            win.FILE_SHARE_WRITE | win.FILE_SHARE_READ,
            &sec_attrs,
            win.OPEN_EXISTING,
            win.FILE_ATTRIBUTE_NORMAL,
            nil,
        )
        assert(dev_null != win.INVALID_HANDLE_VALUE, "could not open NUL device")
        start_info.hStdOutput = dev_null
        start_info.hStdError = dev_null
        start_info.dwFlags |= win.STARTF_USESTDHANDLES
    } else if option == .Capture {
        pipe_init(&stdout_pipe, &sec_attrs) or_return
        pipe_init(&stderr_pipe, &sec_attrs) or_return
        start_info.hStdOutput = stdout_pipe.write
        start_info.hStdError = stderr_pipe.write
        start_info.dwFlags |= win.STARTF_USESTDHANDLES
    }

    defer if option == .Silent {
        handle_close(dev_null)
    }
    defer if option == .Capture {
        pipe_close_write(stderr_pipe)
        pipe_close_write(stdout_pipe)
    }
    defer if err != nil {
        pipe_close_read(stdout_pipe)
        pipe_close_read(stderr_pipe)
    }

    cmd := combine_args(prog, args, context.temp_allocator)
    print_cmd(option, prog, args, loc)

    proc_info: win.PROCESS_INFORMATION
    // NOTE: Environment variables of the calling process are passed
    if !win.CreateProcessW(
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
    ) {
        err = General_Error.Program_Not_Executed
        return
    }
    execution_time := time.now()

    maybe_stdout_pipe: Maybe(_Pipe) = (option == .Capture) ? stdout_pipe : nil
    maybe_stderr_pipe: Maybe(_Pipe) = (option == .Capture) ? stderr_pipe : nil
    return Process {
            handle = {proc_info.hProcess, proc_info.hThread},
            execution_time = execution_time,
            stdout_pipe = maybe_stdout_pipe,
            stderr_pipe = maybe_stderr_pipe,
        },
        err
}


_program :: proc($name: string, loc: Loc) -> (found: bool) {
    res, err := run_prog_sync_unchecked(
        "cmd",
        {"/C where " + name + " && exit 0 || exit 1"},
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
    // `pipe_read`
    Pipe_Read_Failed,
    // `handle_close`
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

pipe_close_read :: proc(self: Pipe) -> (err: Error) {
    return nil if win.CloseHandle(self.read) else Internal_Error.Pipe_Close_Failed
}

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

handle_close :: proc(handle: win.HANDLE) -> Error {
    return nil if win.CloseHandle(handle) else Internal_Error.Handle_Close_Failed
}

