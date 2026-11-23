;;; run-code-commands.el --- Interactive commands and public API -*- lexical-binding: t; -*-

(require 'run-code-core)
(require 'run-code-buffer)

;;;###autoload
(defun run-code-dev ()
  "Run the current file in development mode."
  (interactive) (run-code--run 'dev))

(autoload 'swiftui-preview-generate "swiftui-preview" nil t)

;;;###autoload
(defun run-code-preview ()
  "Generate the SwiftUI preview for the current Swift buffer."
  (interactive)
  (unless (memq major-mode '(swift-mode swift-ts-mode))
    (user-error "SwiftUI preview is only available in Swift buffers"))
  (run-code--check-file)
  (unless (fboundp 'swiftui-preview-generate)
    (user-error "swiftui-preview-generate is unavailable; load swiftui-preview.el first"))
  (call-interactively #'swiftui-preview-generate))

;;;###autoload
(defun run-code-opt ()
  "Run the current file in optimized mode."
  (interactive) (run-code--run 'opt))

;;;###autoload
(defun run-code-test ()
  "Run tests for the current project or file."
  (interactive) (run-code--run 'test))

;;;###autoload
(defun run-code-set (filetype command)
  "Set development and optimized COMMAND for FILETYPE."
  (interactive (list (read-string "Major mode: ") (read-string "Command: ")))
  (setf (alist-get filetype run-code-commands nil nil #'equal) command))

;;;###autoload
(defun run-code-set-test (filetype command)
  "Set test COMMAND for FILETYPE."
  (interactive (list (read-string "Major mode: ") (read-string "Test command: ")))
  (setf (alist-get filetype run-code-test-commands nil nil #'equal) command))

;;;###autoload
(defun run-code-list ()
  "Display supported major modes."
  (interactive)
  (message "Supported modes: %s"
           (mapconcat #'symbol-name (run-code-supported-languages) ", ")))

;;;###autoload
(defun run-code-config ()
  "Open the run-code customization group."
  (interactive) (customize-group 'run-code))

;;;###autoload
(defun run-code-show-output ()
  "Display the most recently used run-code output buffer."
  (interactive)
  (let ((buffer (and (buffer-live-p run-code-last-output-buffer)
                     run-code-last-output-buffer)))
    (unless buffer (user-error "No run-code output buffer exists"))
    (run-code--display-output-buffer buffer)))

(provide 'run-code-commands)
;;; run-code-commands.el ends here
