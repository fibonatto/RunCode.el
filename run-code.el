;;; run-code.el --- Run source files from Emacs -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "27.1"))
;; Version: 0.1.0
;; Keywords: tools, processes, convenience

;;; Commentary:
;; Run source files asynchronously and display output in ordinary Emacs
;; buffers.  The default backend does not start an interactive terminal.
;; Load optional integrations explicitly, for example `run-code-evil'.

;;; Code:

(require 'run-code-config)
(require 'run-code-utils)
(require 'run-code-language)
(require 'run-code-buffer)
(require 'run-code-process)
(require 'run-code-core)
(require 'run-code-commands)
(require 'run-code-mode)

(autoload 'run-code-lean-check "run-code-lean" nil t)

(provide 'run-code)
;;; run-code.el ends here
