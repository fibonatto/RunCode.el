;;; run-code-lean.el --- Lean integration -*- lexical-binding: t; -*-

(require 'run-code-core)

(defun run-code-lean-check ()
  "Check the current Lean file's types without building the project."
  (interactive)
  (unless (derived-mode-p 'lean4-mode)
    (user-error "Current buffer is not a Lean buffer"))
  (run-code--run 'dev))

(provide 'run-code-lean)
;;; run-code-lean.el ends here
