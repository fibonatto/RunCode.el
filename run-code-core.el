;;; run-code-core.el --- Execution orchestration -*- lexical-binding: t; -*-

(require 'run-code-config)
(require 'run-code-utils)
(require 'run-code-language)
(require 'run-code-buffer)
(require 'run-code-process)

(defun run-code--backend (operation)
  (or (cl-loop for (mode op backend) in run-code-backend-overrides
               when (and (equal mode (symbol-name major-mode))
                         (eq op operation))
               return backend)
      (run-code--registered-property major-mode :backend)
      run-code-default-backend))

(defun run-code--run (operation)
  "Execute OPERATION (`dev', `opt' or `test') for the current source buffer."
  (let* ((file (run-code--check-file))
         (command (run-code--get-command operation))
         (backend (run-code--backend operation)))
    (unless (and (stringp command) (not (string-empty-p command)))
      (user-error "No %s command configured for %s" operation major-mode))
    (unless (memq backend '(buffer compilation terminal))
      (user-error "Unsupported run-code backend: %s" backend))
    (let* ((expanded (run-code--expand-placeholders command))
           (directory (file-name-directory file)))
      (when run-code-show-feedback
        (message "run-code: starting %s (%s)" operation backend))
      (pcase backend
        ('compilation
         (require 'run-code-compilation)
         (let ((default-directory directory))
           (run-code-compilation-start expanded operation)))
        ('buffer
         (let ((buffer (run-code--output-buffer operation)))
           (run-code--prepare-output-buffer buffer (current-buffer))
           (run-code--display-output-buffer buffer)
           (run-code-start-process expanded buffer directory
                                   (format "run-code-%s-%s" major-mode operation))))
        ('terminal
         (require 'run-code-terminal)
         (setq run-code-last-process (run-code-terminal-run expanded directory)))))))

(provide 'run-code-core)
;;; run-code-core.el ends here
