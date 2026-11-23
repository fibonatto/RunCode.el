;;; run-code-utils.el --- Internal utilities -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)

(defun run-code--file ()
  "Return the current buffer's file name or signal a user error."
  (or buffer-file-name (user-error "Current buffer is not visiting a file")))

(defun run-code--file-directory ()
  "Return the directory containing the current file."
  (file-name-directory (expand-file-name (run-code--file))))

(defun run-code--check-file ()
  "Validate the current file and save it when configured."
  (let ((file (run-code--file)))
    (unless (file-readable-p file)
      (user-error "File is not readable: %s" file))
    (when (and run-code-auto-save (buffer-modified-p))
      (save-buffer))
    file))

(defun run-code--buffer-text ()
  "Return the current buffer contents without text properties."
  (buffer-substring-no-properties (point-min) (point-max)))

(defun run-code--makefile-p ()
  "Return non-nil when the current directory contains a Makefile."
  (seq-some #'file-readable-p '("Makefile" "makefile" "GNUmakefile")))

(defun run-code--placeholder-file (modifiers)
  "Resolve file placeholder MODIFIERS to a shell-quoted file name."
  (let* ((absolute (member "p" modifiers))
         (file (if absolute
                   (expand-file-name (run-code--file))
                 (let ((name (expand-file-name (run-code--file))))
                   (if (file-in-directory-p name (expand-file-name default-directory))
                       (file-relative-name name default-directory)
                     name)))))
    (dolist (modifier modifiers)
      (setq file
            (pcase modifier
              ("p" (expand-file-name file))
              ("t" (file-name-nondirectory file))
              ("h" (or (file-name-directory file) "."))
              ("r" (file-name-sans-extension file))
              ("e" (or (file-name-extension file) ""))
              (_ file))))
    (shell-quote-argument file)))

(defun run-code--expand-placeholders (command)
  "Expand run-code file placeholders in COMMAND.
Supported forms: %, %%, %<, %:p, %:t, %:h, %:r and %:e.
A placeholder is shell-quoted.  COMMAND itself is trusted shell syntax."
  (let ((i 0) (n (length command)) pieces)
    (while (< i n)
      (if (/= (aref command i) ?%)
          (progn (push (char-to-string (aref command i)) pieces)
                 (setq i (1+ i)))
        (if (and (< (1+ i) n) (= (aref command (1+ i)) ?%))
            (progn (push "%" pieces) (setq i (+ i 2)))
          (let ((j (1+ i)) modifiers)
            (if (and (< j n) (= (aref command j) ?<))
                (setq modifiers '("r") j (1+ j))
              (while (and (< j n) (= (aref command j) ?:)
                          (< (1+ j) n)
                          (memq (aref command (1+ j)) '(?p ?t ?h ?r ?e)))
                (push (char-to-string (aref command (1+ j))) modifiers)
                (setq j (+ j 2)))
              (setq modifiers (nreverse modifiers)))
            (push (run-code--placeholder-file modifiers) pieces)
            (setq i j)))))
    (apply #'concat (nreverse pieces))))

(provide 'run-code-utils)
;;; run-code-utils.el ends here
