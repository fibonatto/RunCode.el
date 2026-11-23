;;; run-code-evil.el --- Optional Evil integration -*- lexical-binding: t; -*-

(require 'run-code-mode)

(with-eval-after-load 'evil
  (evil-define-key 'normal run-code-mode-map
    (kbd "r") #'run-code-dev
    (kbd "R") #'run-code-opt
    (kbd "t") #'run-code-test))

(provide 'run-code-evil)
;;; run-code-evil.el ends here
