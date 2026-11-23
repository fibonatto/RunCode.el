;;; run-code-test.el --- Tests for run-code -*- lexical-binding: t; -*-

(require 'ert)
(require 'run-code)

(ert-deftest run-code-placeholder-expansion-basic ()
  (with-temp-buffer
    (let* ((file (make-temp-file "run-code" nil ".py"))
           (buffer-file-name file)
           (default-directory (file-name-directory file)))
      (should (equal (run-code--expand-placeholders "python %")
                     (concat "python " (shell-quote-argument (file-name-nondirectory file)))))
      (should (equal (run-code--expand-placeholders "echo %%") "echo %"))
      (should (equal (run-code--expand-placeholders "echo %:e") "echo py"))
      (delete-file file))))

(ert-deftest run-code-language-resolution ()
  (with-temp-buffer
    (setq major-mode 'python-mode)
    (let ((run-code-commands '(("python-mode" . "custom-run %"))))
      (should (string-prefix-p "custom-run " (run-code--get-command 'dev))))))

(ert-deftest run-code-language-registration ()
  (let ((run-code-language-registry nil))
    (run-code-register-language 'sample-mode :dev "sample %" :test "sample-test")
    (with-temp-buffer
      (setq major-mode 'sample-mode)
      (should (equal (run-code--get-command 'dev) "sample %"))
      (should (equal (run-code--get-command 'test) "sample-test")))))

(ert-deftest run-code-lean-check-does-not-build ()
  (with-temp-buffer
    (setq major-mode 'lean4-mode)
    (cl-letf (((symbol-function 'run-code--lean-project-p) (lambda () t)))
      (should (equal (run-code--lean-check-command) "lake env lean %")))))

(provide 'run-code-test)
;;; run-code-test.el ends here
