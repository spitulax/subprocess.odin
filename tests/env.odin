package tests

import lib ".."
import "core:fmt"
import "core:os"
import "core:testing"

var :: proc($name: string) -> string {
    when ODIN_OS in lib.POSIX_OS {
        return "$" + name
    } else when ODIN_OS in lib.WINDOWS_OS {
        return "%" + name + "%"
    }
}

echo :: proc($name: string) -> string {
    return fmt.tprint("echo", var(name))
}

when ODIN_OS in lib.POSIX_OS {
    USER :: "USER"
} else when ODIN_OS in lib.WINDOWS_OS {
    USER :: "USERNAME"
}

@(test)
env :: proc(t: ^testing.T) {
    lib.default_flags_enable({.Use_Context_Logger, .Echo_Commands})

    result: lib.Result
    ok: bool

    result, ok = lib.unwrap(
        lib.run_shell_sync(echo(USER), {output = .Capture, inherit_env = true}),
    )
    if ok {
        defer lib.result_destroy(&result)
        testing.expect_value(t, trim_nl(result.stdout), os.get_env(USER, context.temp_allocator))
    }

    result, ok = lib.unwrap(lib.run_shell_sync(echo(USER), {output = .Capture}))
    if ok {
        defer lib.result_destroy(&result)
        when ODIN_OS in lib.POSIX_OS {
            testing.expect_value(t, trim_nl(result.stdout), "")
        } else when ODIN_OS in lib.WINDOWS_OS {
            testing.expect_value(t, trim_nl(result.stdout), var(USER))
        }
    }

    result, ok = lib.unwrap(
        lib.run_shell_sync(
            echo("MY_VARIABLE"),
            {output = .Capture, extra_env = {"MY_VARIABLE=foobar"}},
        ),
    )
    if ok {
        defer lib.result_destroy(&result)
        testing.expect_value(t, trim_nl(result.stdout), "foobar")
    }

    result, ok = lib.unwrap(
        lib.run_shell_sync(
            echo("MY_VARIABLE"),
            {output = .Capture, extra_env = {"MY_VARIABLE=foobar"}, inherit_env = true},
        ),
    )
    if ok {
        defer lib.result_destroy(&result)
        testing.expect_value(t, trim_nl(result.stdout), "foobar")
    }
}

