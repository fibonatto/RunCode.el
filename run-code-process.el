;;; run-code-process.el --- Asynchronous process management -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'run-code-config)
(require 'run-code-buffer)

(defvar run-code-processes nil
  "List of live processes started by run-code.")
(defvar run-code-last-process nil
  "Most recently started run-code process.")

(defun run-code--process-finished (process _event)
  (when (memq (process-status process) '(exit signal))
    (let* ((status (process-exit-status process))
           (timed-out (process-get process 'run-code-timed-out))
           (buffer (process-buffer process))
           (timer (process-get process 'run-code-timeout-timer)))
      (when (timerp timer) (cancel-timer timer))
      (setq run-code-processes (delq process run-code-processes))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (let* ((inhibit-read-only t)
                 (started (process-get process 'run-code-start-time))
                 (elapsed (and started (- (float-time) started))))
            (goto-char (point-max))
            (insert (format "\n[run-code] %s (exit %d%s)\n"
                            (cond (timed-out "Timed out")
                                  ((zerop status) "Finished")
                                  (t "Failed"))
                            status (if elapsed (format ", %.3fs" elapsed) ""))))))
      (when run-code-show-feedback
        (message "run-code: %s (exit %d)"
                 (cond (timed-out "timed out")
                       ((zerop status) "finished")
                       (t "failed")) status))
      (when (and (zerop status) run-code-buffer-auto-close
                 (buffer-live-p buffer))
        (when-let* ((window (get-buffer-window buffer)))
          (run-at-time 0.2 nil
                       (lambda (win) (when (window-live-p win) (delete-window win)))
                       window))))))

(defun run-code--process-timeout (process)
  (when (process-live-p process)
    (process-put process 'run-code-timed-out t)
    (delete-process process)))

(defun run-code-start-process (command buffer directory &optional name)
  "Start shell COMMAND asynchronously in BUFFER with DIRECTORY as cwd.
Return the process object.  COMMAND is trusted user configuration and is
passed to the user's shell."
  (let* ((default-directory (file-name-as-directory (expand-file-name directory)))
         (process-environment (copy-sequence process-environment))
         (process (make-process
                   :name (or name "run-code")
                   :buffer buffer
                   :stderr buffer
                   :command (list shell-file-name shell-command-switch command)
                   :connection-type 'pipe
                   :noquery t
                   :sentinel #'run-code--process-finished)))
    (with-current-buffer buffer (setq-local run-code-buffer-process process))
    (process-put process 'run-code-command command)
    (process-put process 'run-code-start-time (float-time))
    (when (> run-code-timeout 0)
      (process-put process 'run-code-timeout-timer
                   (run-at-time run-code-timeout nil #'run-code--process-timeout process)))
    (push process run-code-processes)
    (setq run-code-last-process process)
    process))

(defun run-code-stop-process (&optional process)
  "Stop PROCESS, defaulting to the most recently started process."
  (interactive)
  (let ((target (or process run-code-last-process)))
    (unless (and target (process-live-p target))
      (user-error "No live run-code process"))
    (interrupt-process target)))

(defun run-code-kill-process (&optional process)
  "Kill PROCESS, defaulting to the most recently started process."
  (interactive)
  (let ((target (or process run-code-last-process)))
    (unless (and target (process-live-p target))
      (user-error "No live run-code process"))
    (delete-process target)))

(provide 'run-code-process)
;;; run-code-process.el ends here
