;;; run-code-buffer.el --- Output buffer presentation -*- lexical-binding: t; -*-

(require 'run-code-config)

(require 'run-code-language)

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
    (run-code--configure-output-font-lock source)
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

(defconst run-code--base-output-font-lock-keywords
  '(("^\\(Run-code\\|Directory\\):" (1 'font-lock-comment-face))
    ("^\\([^:\n]+:[0-9]+:[0-9]+:\\) \\(error\\):"   (1 'shadow) (2 'error))
    ("^\\([^:\n]+:[0-9]+:[0-9]+:\\) \\(warning\\):" (1 'shadow) (2 'warning))
    ("^\\([^:\n]+:[0-9]+:[0-9]+:\\) \\(note\\|info\\):" (1 'shadow) (2 'success))
    ("^\\[run-code\\] Failed.*$"   . 'error)
    ("^\\[run-code\\] Finished.*$" . 'success)
    ("^Process .* finished$" . 'shadow))
  "Base font-lock rules shared across all run-code output buffers.")

(defconst run-code--rust-font-lock-keywords
  '(("^\\(error\\(?:\\[E[0-9]+\\]\\)?\\):" (1 'error))
    ("^\\(warning\\(?:\\[[^]]+\\]\\)?\\):" (1 'warning))
    ("^\\s-*\\(-->\\)\\s-+\\([^:\n]+:[0-9]+:[0-9]+\\)"
     (1 'font-lock-builtin-face) (2 'shadow))
    ("^test .+ \\.\\.\\. \\(ok\\)$"     (1 'success))
    ("^test .+ \\.\\.\\. \\(FAILED\\)$" (1 'error))))

(defconst run-code--python-font-lock-keywords
  '(("^\\s-*File \\(\"[^\"]+\"\\), line \\([0-9]+\\)"
     (1 'shadow) (2 'font-lock-constant-face))
    ("^\\([A-Za-z_][A-Za-z0-9_.]*\\(?:Error\\|Exception\\)\\):" (1 'error))
    ("\\_<\\(PASSED\\)\\_>" (1 'success))
    ("\\_<\\(FAILED\\|ERROR\\)\\_>" (1 'error))))

(defconst run-code--agda-font-lock-keywords
  '(("^—+$" . 'font-lock-preprocessor-face)
    ("\\?[0-9]+\\|{![^!]*!}" . 'warning)
    ("^\\([^:\n]+\\)\\s-+:\\s-+" (1 'font-lock-function-name-face))
    ("[∀∃→↔λΠΣ≡≢]" . 'font-lock-builtin-face)))

(defconst run-code--lean-font-lock-keywords
  '(("^── .* ──$" . 'font-lock-preprocessor-face)
    ("^\\(theorem\\|ctor\\|def\\|axiom\\|opaque\\|variable\\)\\_>\\s-+\\([^ \t\n:]+\\)"
     (1 'font-lock-keyword-face)
     (2 'font-lock-function-name-face))
    ("^\\(sorry\\)\\_>\\s-+\\([^ \t\n:]+\\)"
     (1 'warning)
     (2 'font-lock-function-name-face))
    ("^⊢" . 'warning)
    ("\\_<\\(forall\\|exists\\|fun\\|let\\|in\\|if\\|then\\|else\\|match\\|with\\|by\\|sorry\\)\\_>"
     . 'font-lock-keyword-face)
    ("\\_<\\(Nat\\|Int\\|Bool\\|Prop\\|Type\\|Sort\\|String\\|List\\|Option\\|True\\|False\\|Fin\\|Unit\\)\\_>"
     . 'font-lock-type-face)
    ("[∀∃→↔∧∨¬⊢≤≥≠∣×∑∏]" . 'font-lock-builtin-face)
    ("\\_<[0-9]+\\_>" . 'font-lock-constant-face))
  "Font-lock keywords for Lean output in `run-code-output-mode'.")

(defun run-code--language-font-lock-keywords (mode)
  "Return language-specific font-lock keywords registered for MODE."
  (let ((kw-sym
         (or (run-code--registered-property mode :font-lock)
             (cl-loop for (reg-mode . props) in run-code-language-registry
                      when (provided-mode-derived-p mode reg-mode)
                      return (plist-get props :font-lock)))))
    (and kw-sym (boundp kw-sym) (symbol-value kw-sym))))

(defun run-code--configure-output-font-lock (source)
  "Configure base and language-specific font-lock for SOURCE."
  (let* ((source-mode (buffer-local-value 'major-mode source))
         (lang-kws (run-code--language-font-lock-keywords source-mode))
         (keywords (append run-code--base-output-font-lock-keywords lang-kws)))
    (setq-local font-lock-defaults (list keywords t))
    (setq-local font-lock-set-defaults nil)
    (font-lock-mode 1)
    (font-lock-set-defaults)
    (font-lock-flush)))

(provide 'run-code-buffer)
;;; run-code-buffer.el ends here
