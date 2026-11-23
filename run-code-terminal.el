;;; run-code-terminal.el --- Optional interactive shell backend -*- lexical-binding: t; -*-

(require 'comint)
(require 'run-code-config)

(defun run-code-terminal-run (command directory)
  "Run COMMAND in an interactive shell rooted at DIRECTORY.
This backend is intended only for programs that require terminal input."
  (let* ((buffer (get-buffer-create run-code-terminal-buffer-name))
         (default-directory (file-name-as-directory (expand-file-name directory))))
    (with-current-buffer buffer
      (unless (comint-check-proc buffer)
        (let ((shell (or (getenv "SHELL") shell-file-name)))
          (make-comint-in-buffer "run-code" buffer shell nil "-i")))
      (when run-code-terminal-clear
        (let ((inhibit-read-only t)) (erase-buffer)))
      (goto-char (point-max)))
    (display-buffer
     buffer
     `((display-buffer-in-side-window)
       (side . ,run-code-terminal-position)
       (slot . 1)
       (window-width . ,run-code-terminal-width)
       (window-height . ,run-code-terminal-height)))
    (with-current-buffer buffer
      (comint-send-string
       (get-buffer-process buffer)
       (format "cd %s && %s\n"
               (shell-quote-argument directory) command)))
    (get-buffer-process buffer)))

(provide 'run-code-terminal)
;;; run-code-terminal.el ends here
