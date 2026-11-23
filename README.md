# run-code

A small, extensible Emacs package for running source files and project tasks.
Its default execution backend uses asynchronous Emacs processes and displays
stdout/stderr in an ordinary buffer. It does not open an interactive terminal.

## Installation

Clone or copy this directory, then add it to `load-path`:

```elisp
(add-to-list 'load-path "~/path/to/run-code")
(require 'run-code)
```

Optional Evil integration:

```elisp
(require 'run-code-evil)
```

Enable automatic activation for supported major modes:

```elisp
(run-code-global-mode 1)
```

## Commands

- `M-x run-code-dev`: development execution.
- `M-x run-code-opt`: optimized execution.
- `M-x run-code-preview`: invoke the optional `swiftui-preview` integration.
- `M-x run-code-test`: test command.
- `M-x run-code-show-output`: show the output buffer.
- `M-x run-code-stop-process`: interrupt the most recent run-code process.
- `M-x run-code-kill-process`: terminate the most recent run-code process.
- `M-x run-code-list`: list supported major modes.
- `M-x run-code-config`: customize the package.

Default minor-mode bindings are `C-c C-r`, `C-c C-o`, `C-c C-t`, and `C-c C-k` (kill current run).

## Configuration

All options are under `M-x customize-group RET run-code`.

```elisp
(setq run-code-auto-save t
      run-code-default-backend 'buffer
      run-code-buffer-clear t
      run-code-timeout 0)
```

The output buffer is selected by `run-code-buffer-name-function`, which
receives the major mode and operation. The default is `*run-code*`.

## Commands and placeholders

Commands are shell command strings. The package expands these placeholders
before passing the command to the configured shell:

| Placeholder | Meaning |
| --- | --- |
| `%` | Current file, relative to `default-directory` when possible |
| `%%` | Literal percent sign |
| `%:p` | Absolute file path |
| `%:t` | File name without directory |
| `%:h` | File directory |
| `%:r` | File name without extension |
| `%:e` | File extension |
| `%<` | File name without extension |

Placeholder values are shell-quoted. Command strings themselves are trusted
configuration and may contain shell syntax such as pipes, redirections and
`&&`.

User-defined commands take precedence over built-in commands:

```elisp
(setq run-code-commands
      '(("python-mode" . "python -u %")
        ("python-ts-mode" . "python -u %")))

(setq run-code-test-commands
      '(("python-mode" . "python -m pytest")))
```

## Language registry

A language can be registered without editing the package:

```elisp
(run-code-register-language
 'example-mode
 :dev "example-run %"
 :opt "example-run --optimized %"
 :test "example-test")
```

A command may also be a zero-argument function returning a command string.

## Backends

- `buffer`: asynchronous `make-process`, output in an Emacs buffer. Default.
- `compilation`: `compilation-start`, with compilation-mode diagnostics.
- `terminal`: optional persistent comint shell, only for programs requiring interactive terminal input.

The terminal backend is opt-in and persistent. It uses a comint shell and is
intended for interactive programs. The process timeout applies to the buffer
backend; the persistent terminal shell is controlled with the stop/kill
commands. tmux is intentionally deferred and is not part of this package
version.

## Lean

For `lean4-mode`, `run-code-dev` invokes `lean FILE`, or `lake env lean FILE`
inside a Lake project. This checks the file's elaboration and types. It does
not invoke `lake build` and does not compile the project. `lake test` remains
the configured test operation.

## Tests

Run ERT from the package directory:

```sh
emacs -Q --batch -L . -L test -l test/run-code-test.el -f ert-run-tests-batch-and-exit
```

## License

MIT. See `LICENSE`.
