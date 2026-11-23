;;; run-code-buffer.el --- Output buffer presentation -*- lexical-binding: t; -*-

(require 'run-code-config)
(require 'subr-x)

(defvar-local run-code-buffer-process nil
  "Process currently associated with this output buffer.")
(defvar-local run-code-buffer-source nil
  "Source buffer associated with this output buffer.")

(defvar run-code-last-output-buffer nil
  "Most recently used run-code output buffer.")

(define-derived-mode run-code-output-mode special-mode "Run-Code"
  "Major mode for run-code process output."
  ;; Output buffers are transient panels, not source buffers.
  ;; Also disable line numbers if a global mode enables them later.
  (add-hook 'display-line-numbers-mode-hook
            #'run-code--disable-output-line-numbers nil t)
  (when (bound-and-true-p display-line-numbers-mode)
    (display-line-numbers-mode -1)))

(defun run-code--disable-output-line-numbers ()
  "Disable line numbers in run-code output buffers."
  (when (and (derived-mode-p 'run-code-output-mode)
             (bound-and-true-p display-line-numbers-mode))
    (display-line-numbers-mode -1)))

(defun run-code--output-buffer (operation)
  (let* ((name (funcall run-code-buffer-name-function major-mode operation))
         (buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'run-code-output-mode)
        (run-code-output-mode))
      ;; Keep the output buffer read-only for interactive editing.
      (setq-local buffer-read-only t))
    (setq run-code-last-output-buffer buffer)
    buffer))

(defun run-code--display-output-buffer (buffer)
  (display-buffer
   buffer
   `((display-buffer-in-side-window)
     (side . ,run-code-buffer-display)
     (slot . 0)
     (window-height . ,run-code-buffer-height)
     (window-width . ,run-code-buffer-width))))

(defun run-code--prepare-output-buffer (buffer source)
  (with-current-buffer buffer
    (when (and run-code-cancel-previous-process
               (processp run-code-buffer-process)
               (process-live-p run-code-buffer-process))
      (delete-process run-code-buffer-process))
    (let ((inhibit-read-only t))
      (when run-code-buffer-clear (erase-buffer))
      (goto-char (point-max))
      (setq-local run-code-buffer-source source)
      (setq-local buffer-read-only t)
      (insert (format "Run-code: %s\nDirectory: %s\n\n"
                      (buffer-name source) (buffer-local-value 'default-directory source))))))

(defun run-code-close ()
  "Close the run-code output window without killing its buffer."
  (interactive)
  (let ((buffer (and (buffer-live-p run-code-last-output-buffer)
                     run-code-last-output-buffer)))
    (unless buffer (user-error "No run-code output buffer exists"))
    (when-let* ((window (get-buffer-window buffer)))
      (delete-window window))))

(provide 'run-code-buffer)
;;; run-code-buffer.el ends here
