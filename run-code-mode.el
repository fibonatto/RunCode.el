;;; run-code-mode.el --- Minor modes and keymaps -*- lexical-binding: t; -*-

(require 'run-code-language)
(require 'run-code-commands)

(defvar run-code-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-r") #'run-code-dev)
    (define-key map (kbd "C-c C-o") #'run-code-opt)
    (define-key map (kbd "C-c C-t") #'run-code-test)
    (define-key map (kbd "C-c C-k") #'run-code-kill-process)
    map)
  "Keymap for `run-code-mode'.")

;;;###autoload
(define-minor-mode run-code-mode
  "Minor mode providing commands to run the current source file."
  :lighter " RunCode" :keymap run-code-mode-map)

(defun run-code--enable-supported-mode ()
  (when (and buffer-file-name (run-code--has-command-p major-mode))
    (run-code-mode 1)))

;;;###autoload
(define-minor-mode run-code-global-mode
  "Enable `run-code-mode' in supported file buffers."
  :global t :group 'run-code
  (if run-code-global-mode
      (add-hook 'after-change-major-mode-hook #'run-code--enable-supported-mode)
    (remove-hook 'after-change-major-mode-hook #'run-code--enable-supported-mode))
  (when run-code-global-mode (run-code--enable-supported-mode)))

(provide 'run-code-mode)
;;; run-code-mode.el ends here
