;;; run-code-config.el --- User options for run-code -*- lexical-binding: t; -*-

(require 'custom)

(defgroup run-code nil
  "Run and inspect source files from Emacs."
  :group 'tools
  :prefix "run-code-")

(defcustom run-code-auto-save t
  "Whether to save a modified file before executing it."
  :type 'boolean :group 'run-code)

(defcustom run-code-show-feedback t
  "Whether to report execution status in the echo area."
  :type 'boolean :group 'run-code)

(defcustom run-code-timeout 0
  "Maximum process duration in seconds.  Zero disables the timeout."
  :type 'number :group 'run-code)

(defcustom run-code-temp-dir temporary-file-directory
  "Directory for temporary build artifacts."
  :type 'directory :group 'run-code)

(defcustom run-code-default-backend 'buffer
  "Backend used unless an operation or language overrides it."
  :type '(choice (const buffer) (const compilation) (const terminal)) :group 'run-code)

(defcustom run-code-buffer-name-function
  (lambda (_mode _operation) "*run-code*")
  "Function returning the output buffer name.
The function receives the major mode and operation symbol."
  :type 'function :group 'run-code)

(defcustom run-code-buffer-clear t
  "Whether to clear an output buffer before starting a new process."
  :type 'boolean :group 'run-code)

(defcustom run-code-cancel-previous-process t
  "Whether a new run cancels a live process already attached to its output buffer."
  :type 'boolean :group 'run-code)

(defcustom run-code-buffer-display 'right
  "Side on which run-code output buffers are displayed."
  :type '(choice (const bottom) (const right) (const left) (const top))
  :group 'run-code)

(defcustom run-code-buffer-height 12
  "Height used when displaying output at the top or bottom."
  :type 'integer :group 'run-code)

(defcustom run-code-buffer-width 0.4
  "Width used when displaying output at the left or right."
  :type 'number :group 'run-code)

(defcustom run-code-buffer-auto-close nil
  "Whether to close the output window after successful execution."
  :type 'boolean :group 'run-code)

(defcustom run-code-terminal-buffer-name "*run-code-terminal*"
  "Name of the optional interactive terminal buffer."
  :type 'string :group 'run-code)

(defcustom run-code-terminal-position 'right
  "Side on which the interactive terminal is displayed."
  :type '(choice (const bottom) (const right) (const left) (const top))
  :group 'run-code)

(defcustom run-code-terminal-width 40
  "Width of the terminal side window."
  :type 'integer :group 'run-code)

(defcustom run-code-terminal-height 12
  "Height of the terminal side window."
  :type 'integer :group 'run-code)

(defcustom run-code-terminal-clear t
  "Whether to clear the terminal buffer before sending a command."
  :type 'boolean :group 'run-code)

(defcustom run-code-python-venv-directories '(".venv" "venv" "env")
  "Project-local Python virtual environment directory names."
  :type '(repeat string) :group 'run-code)

(defcustom run-code-commands nil
  "User-defined development or optimized commands, keyed by major-mode name.
A value may be a shell command string or a function returning one."
  :type '(alist :key-type string :value-type sexp) :group 'run-code)

(defcustom run-code-test-commands nil
  "User-defined test commands, keyed by major-mode name."
  :type '(alist :key-type string :value-type sexp) :group 'run-code)

(defcustom run-code-backend-overrides nil
  "Per-operation backend overrides.
Each entry is (MODE OPERATION BACKEND).  BACKEND is `buffer',
`compilation' or `terminal'."
  :type '(repeat (list (string :tag "Major mode")
                       (choice (const dev) (const opt) (const test))
                       (choice (const buffer) (const compilation) (const terminal))))
  :group 'run-code)

(provide 'run-code-config)
;;; run-code-config.el ends here
