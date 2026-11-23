;;; run-code-compilation.el --- Compilation backend -*- lexical-binding: t; -*-

(require 'compile)
(require 'run-code-config)

(defun run-code-compilation-start (command operation)
  "Run COMMAND through Emacs compilation facilities for OPERATION."
  (let ((compilation-buffer-name-function
         (lambda (_mode) (format "*run-code: %s*" operation))))
    (compilation-start command 'compilation-mode)))

(provide 'run-code-compilation)
;;; run-code-compilation.el ends here
