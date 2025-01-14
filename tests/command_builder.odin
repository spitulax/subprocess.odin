package tests

import lib ".."
import "core:testing"

@(private = "file")
test :: proc(t: ^testing.T, cmd: lib.Command) -> bool {
    {
        results: [3]lib.Result
        results[0] = lib.unwrap(lib.command_run(cmd)) or_return
        results[1] = lib.unwrap(lib.command_run(cmd, lib.Exec_Opts{output = .Capture})) or_return
        results[2] = lib.unwrap(lib.command_run(cmd, lib.Exec_Opts{output = .Silent})) or_return
        defer lib.result_destroy_many(results[:])
        for &x, i in results {
            expect_result(t, x, "Hello, World!" + NL if i == 1 else "", "")
        }
    }

    {
        PROCESSES :: 5
        processes: [PROCESSES]lib.Process
        for &process in processes {
            process = lib.unwrap(
                lib.command_run_async(cmd, lib.Exec_Opts{output = .Capture}),
            ) or_return
        }
        res := lib.unwrap(lib.process_wait_many(processes[:])) or_return
        defer lib.result_destroy_many(res)
        testing.expect_value(t, len(res), PROCESSES)
        for x in res {
            expect_result(t, x, "Hello, World!" + NL, "")
        }
    }

    return true
}

@(test)
command_builder :: proc(t: ^testing.T) {
    {
        cmd := lib.unwrap(lib.command_make(SH))
        defer lib.command_destroy(&cmd)
        if !testing.expect(t, cmd.prog.found) {return}
        lib.command_append(&cmd, CMD)
        lib.command_append(&cmd, "echo Hello, World!")
        test(t, cmd)
    }

    {
        cmd: lib.Command
        lib.unwrap(lib.command_init(&cmd, SH))
        defer lib.command_destroy(&cmd)
        if !testing.expect(t, cmd.prog.found) {return}
        lib.command_append(&cmd, CMD)
        lib.command_append(&cmd, "echo Hello, World!")
        test(t, cmd)
    }
}

@(test)
command_args :: proc(t: ^testing.T) {
    cmd, cmd_ok := lib.unwrap(lib.command_make(SH))
    if !cmd_ok {return}
    defer lib.command_destroy(&cmd)

    lib.command_append(&cmd, "Hello")
    expect_array(t, cmd.args[:], []string{"Hello"})

    lib.command_append(&cmd, "World", "Foo", "Baz")
    expect_array(t, cmd.args[:], []string{"Hello", "World", "Foo", "Baz"})

    lib.command_inject_at(&cmd, 3, "Bar")
    expect_array(t, cmd.args[:], []string{"Hello", "World", "Foo", "Bar", "Baz"})

    lib.command_inject_at(&cmd, 2, "FOO", "BAR", "BAZ")
    expect_array(
        t,
        cmd.args[:],
        []string{"Hello", "World", "FOO", "BAR", "BAZ", "Foo", "Bar", "Baz"},
    )

    lib.command_set(&cmd, "HELLO", "WORLD")
    expect_array(t, cmd.args[:], []string{"HELLO", "WORLD"})

    lib.command_clear(&cmd)
    expect_array(t, cmd.args[:], []string{})
}

