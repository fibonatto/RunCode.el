EMACS ?= emacs

.PHONY: test compile lint clean

test:
	$(EMACS) -Q --batch -L . -L test -l test/run-code-test.el -f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch -L . -f batch-byte-compile run-code.el run-code-config.el run-code-utils.el run-code-language.el run-code-buffer.el run-code-process.el run-code-compilation.el run-code-terminal.el run-code-core.el run-code-lean.el run-code-commands.el run-code-mode.el run-code-evil.el

lint:
	$(EMACS) -Q --batch -L . --eval "(progn (require 'package-lint) (package-lint-batch-and-exit \"run-code.el\"))"

clean:
	rm -f *.elc test/*.elc
