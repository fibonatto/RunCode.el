;;; run-code-language.el --- Language command registry -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'seq)
(require 'run-code-config)
(require 'run-code-utils)

(defun run-code--python-venv-executable (directory)
  (cl-loop for executable in '("python" "python3")
           for path = (expand-file-name (concat "bin/" executable) directory)
           when (file-executable-p path) return path))

(defun run-code--find-project-python-venv ()
  (let ((directory (file-name-as-directory (expand-file-name (run-code--file-directory))))
        executable)
    (while (and directory (not executable))
      (setq executable
            (cl-loop for name in run-code-python-venv-directories
                     for path = (expand-file-name name directory)
                     when (file-directory-p path)
                     thereis (run-code--python-venv-executable path)))
      (unless executable
        (let ((parent (file-name-directory (directory-file-name directory))))
          (setq directory (unless (or (null parent) (equal parent directory)) parent)))))
    executable))

(defun run-code--python-executable ()
  (let* ((venv (getenv "VIRTUAL_ENV"))
         (active (and venv (file-directory-p venv)
                      (run-code--python-venv-executable venv))))
    (or active (run-code--find-project-python-venv)
        (executable-find "python3") (executable-find "python")
        (user-error "Python interpreter not found"))))

(defun run-code--python-command (&optional optimized test)
  (concat (shell-quote-argument (run-code--python-executable))
          (cond (test " -m pytest")
                (optimized " -O %")
                (t " -u %"))))

(defun run-code--lean-project-p ()
  (locate-dominating-file
   (run-code--file-directory)
   (lambda (dir) (or (file-readable-p (expand-file-name "lakefile.lean" dir))
                     (file-readable-p (expand-file-name "lakefile.toml" dir))))))

(defun run-code--lean-check-command ()
  "Check Lean types and display useful, categorized declarations."
  (let ((lean-command
         (if (run-code--lean-project-p)
             "lake env lean"
           "lean")))
    (concat
     "tmpdir=$(mktemp -d \"%:h/.run-code.XXXXXX\") || exit 1\n"
     "tmp=\"$tmpdir/Context.lean\"\n"
     "trap 'rm -rf \"$tmpdir\"' EXIT\n"
     "{ echo 'import Lean'; cat %; } > \"$tmp\" || exit 1\n"
     "cat >> \"$tmp\" <<'RUN_CODE_LEAN_CONTEXT'\n"
     "\n"
     "open Lean Elab Command Meta\n"
     "\n"
     "run_cmd do\n"
     "  let isInternal (name : Name) : Bool := Id.run do\n"
     "    let s := name.toString\n"
     "    let last := (s.splitOn \".\").getLast!\n"
     "    last ∈ [\"rec\", \"casesOn\", \"recOn\", \"brecOn\",\n"
     "            \"noConfusion\", \"noConfusionType\", \"ctorIdx\",\n"
     "            \"_f\", \"_unsafe_rec\", \"_sunfold\"] ||\n"
     "    last.startsWith \"match_\" ||\n"
     "    last.startsWith \"eq_\" ||\n"
     "    last.startsWith \"proof_\" ||\n"
     "    s.endsWith \".below\" ||\n"
     "    s.contains \".below.\" ||\n"
     "    s.contains \"._\"\n"
     "\n"
     "  let unfoldProps (propDefs : NameSet) (e : Expr) : CoreM Expr := do\n"
     "    let env ← getEnv\n"
     "    Core.transform e fun sub => do\n"
     "      match sub with\n"
     "      | .const n lvls =>\n"
     "        if propDefs.contains n then\n"
     "          if let some ci := env.find? n then\n"
     "            if let some val := ci.value? then\n"
     "              return .visit (val.instantiateLevelParams ci.levelParams lvls)\n"
     "        return .continue\n"
     "      | _ => return .continue\n"
     "\n"
     "  let env ← getEnv\n"
     "  let infos ← liftIO <| env.getLocalConstantInfos (skipTheoremSubDecls := true)\n"
     "\n"
     "  let mut propDefs : NameSet := {}\n"
     "  for info in infos do\n"
     "    unless isInternal info.name do\n"
     "      match info.toConstantInfo with\n"
     "      | .defnInfo val =>\n"
     "        if val.type == Expr.sort Level.zero && val.safety != .partial then\n"
     "          propDefs := propDefs.insert info.name\n"
     "      | _ => pure ()\n"
     "\n"
     "  let mut thms : Array MessageData := #[]\n"
     "  let mut openGoals : Array MessageData := #[]\n"
     "  let mut ctors : Array MessageData := #[]\n"
     "  let mut defs : Array MessageData := #[]\n"
     "  let mut axioms : Array MessageData := #[]\n"
     "\n"
     "  for info in infos do\n"
     "    unless isInternal info.name do\n"
     "      match info.toConstantInfo with\n"
     "      | .thmInfo val =>\n"
     "        let msg ← liftTermElabM do\n"
     "          let ty ← Core.betaReduce (← unfoldProps propDefs val.type)\n"
     "          let fmt ← ppExpr ty\n"
     "          if val.value.hasSorry then\n"
     "            pure m!\"sorry {info.name} : {fmt}\"\n"
     "          else\n"
     "            pure m!\"theorem {info.name} : {fmt}\"\n"
     "        if val.value.hasSorry then\n"
     "          openGoals := openGoals.push msg\n"
     "        else\n"
     "          thms := thms.push msg\n"
     "      | .ctorInfo val =>\n"
     "        let msg ← liftTermElabM do\n"
     "          let ty ← Core.betaReduce (← unfoldProps propDefs val.type)\n"
     "          let fmt ← ppExpr ty\n"
     "          pure m!\"ctor {info.name} : {fmt}\"\n"
     "        ctors := ctors.push msg\n"
     "      | .defnInfo val =>\n"
     "        unless propDefs.contains info.name do\n"
     "          let last := (info.name.toString.splitOn \".\").getLast!\n"
     "          unless last.endsWith \"Aux\" || last.endsWith \"_aux\" do\n"
     "            let msg ← liftTermElabM do\n"
     "              let fmt ← ppExpr val.type\n"
     "              pure m!\"def {info.name} : {fmt}\"\n"
     "            defs := defs.push msg\n"
     "      | .axiomInfo val =>\n"
     "        let msg ← liftTermElabM do\n"
     "          let ty ← Core.betaReduce (← unfoldProps propDefs val.type)\n"
     "          let fmt ← ppExpr ty\n"
     "          pure m!\"axiom {info.name} : {fmt}\"\n"
     "        axioms := axioms.push msg\n"
     "      | .opaqueInfo val =>\n"
     "        let msg ← liftTermElabM do\n"
     "          let ty ← Core.betaReduce (← unfoldProps propDefs val.type)\n"
     "          let fmt ← ppExpr ty\n"
     "          pure m!\"opaque {info.name} : {fmt}\"\n"
     "        axioms := axioms.push msg\n"
     "      | .inductInfo _ | .recInfo _ | .quotInfo _ => pure ()\n"
     "\n"
     "  let logSection (title : String) (items : Array MessageData) : CommandElabM Unit := do\n"
     "    unless items.isEmpty do\n"
     "      let body := MessageData.joinSep items.toList m!\"\\n\"\n"
     "      logInfo m!\"── {title} ──\\n{body}\"\n"
     "\n"
     "  logSection \"THEOREMS\" thms\n"
     "  logSection \"CONSTRUCTORS\" ctors\n"
     "  logSection \"OPEN GOALS (sorry)\" openGoals\n"
     "  logSection \"AXIOMS / OPAQUE\" axioms\n"
     "  logSection \"DEFINITIONS\" defs\n"
     "\n"
     "  let activeVars ← runTermElabM fun xs => do\n"
     "    let mut vars : Array MessageData := #[]\n"
     "    for x in xs do\n"
     "      let name ← ppExpr x\n"
     "      let type ← ppExpr (← inferType x)\n"
     "      vars := vars.push m!\"variable {name} : {type}\"\n"
     "    pure vars\n"
     "  logSection \"ACTIVE VARIABLES\" activeVars\n"
     "\n"
     "RUN_CODE_LEAN_CONTEXT\n"
     lean-command " \"$tmp\"")))

(defun run-code--c-command ()
  (if (run-code--makefile-p) "make run"
    (concat "clang %" (if (string-match-p "#include[[:space:]]*<cs50\\.h>" (run-code--buffer-text))
                          " -I/usr/local/include -L/usr/local/lib -lcs50" "")
            " -o %:r && ./%:r")))

(defun run-code--c-opt-command ()
  (if (run-code--makefile-p) "make && ./$(basename %:r)"
    (concat "clang -O2 %" (if (string-match-p "#include[[:space:]]*<cs50\\.h>" (run-code--buffer-text))
                                " -I/usr/local/include -L/usr/local/lib -lcs50" "")
            " -o %:r && ./%:r")))

(defun run-code--cpp-command (&optional optimized)
  (concat "clang++ -std=c++17" (if optimized " -O2" "") " %"
          (if (string-match-p "#include[[:space:]]*[<\\\"]llvm/" (run-code--buffer-text))
              " $(llvm-config --cxxflags --ldflags --system-libs --libs all)" "")
          " -o %:r && ./%:r"))

(defun run-code--haskell-opt-command ()
  (let ((exe (expand-file-name (format ".run_code_%d" (emacs-pid)) run-code-temp-dir)))
    (format "ghc -O2 -threaded %% -o %s && %s; rc=$?; rm -f %s %%:r.hi %%:r.o; exit $rc"
            (shell-quote-argument exe) (shell-quote-argument exe)
            (shell-quote-argument exe))))

(defun run-code--typescript-opt-command ()
  (concat "tsc % --outDir " (shell-quote-argument run-code-temp-dir)
          " && node " (shell-quote-argument run-code-temp-dir) "/%:t:r.js"))

(defconst run-code-development-commands
  '(("agda-mode" . "agda-cli check %") ("bend-mode" . "bend %")
    ("c-mode" . run-code--c-command) ("c-ts-mode" . run-code--c-command)
    ("c++-mode" . (lambda () (run-code--cpp-command nil)))
    ("c++-ts-mode" . (lambda () (run-code--cpp-command nil)))
    ("caramel-mode" . "mel main") ("coc-mode" . "coc type %:r && coc norm %:r")
    ("csharp-mode" . "mcs % -out:%:r.exe && mono %:r.exe")
    ("cuda-mode" . "nvcc % -o %:r && ./%:r") ("dart-mode" . "dart %")
    ("dvl-mode" . "dvl run %") ("elm-mode" . "elm make % --output=%:r.js")
    ("erlang-mode" . "escript %") ("go-mode" . "go run %")
    ("haskell-mode" . "stack run") ("html-mode" . "npm run dev")
    ("lean4-mode" . run-code--lean-check-command) ("mhtml-mode" . "npm run dev")
    ("http-mode" . "httpyac --all route.http") ("java-mode" . "javac % && java -cp %:h %:t:r")
    ("js-mode" . "bun run %") ("js-ts-mode" . "bun run %")
    ("lisp-mode" . "sbcl --script %") ("typescript-mode" . "bun run %")
    ("typescript-ts-mode" . "bun run %") ("julia-mode" . "julia %")
    ("kotlin-mode" . "kotlinc % -include-runtime -d %:r.jar && java -jar %:r.jar")
    ("lua-mode" . "lua %") ("nim-mode" . "nim compile --run %")
    ("ocaml-mode" . "ocamlc -o %:r % && ./%:r") ("perl-mode" . "perl -w %")
    ("php-mode" . "php %") ("python-mode" . run-code--python-command)
    ("python-ts-mode" . run-code--python-command) ("r-mode" . "Rscript %")
    ("ruby-mode" . "ruby %") ("rust-mode" . "rustc -O % -o %:r && ./%:r")
    ("rust-ts-mode" . "rustc -O % -o %:r && ./%:r") ("scala-mode" . "scala %")
    ("scheme-mode" . "csc % && ./%:r") ("sh-mode" . "bash -x %")
    ("swift-mode" . "swift %") ("web-mode" . "npm run dev")
    ("zig-mode" . "zig run %")))

(defconst run-code-optimized-commands
  '(("agda-mode" . "agda-cli run %") ("bend-mode" . "bend %")
    ("c-mode" . run-code--c-opt-command) ("c-ts-mode" . run-code--c-opt-command)
    ("c++-mode" . (lambda () (run-code--cpp-command t)))
    ("c++-ts-mode" . (lambda () (run-code--cpp-command t)))
    ("cuda-mode" . "nvcc -O3 % -o %:r && ./%:r")
    ("dart-mode" . "dart compile exe % -o %:r && ./%:r")
    ("go-mode" . "go build -ldflags=\"-s -w\" -o %:r % && ./%:r")
    ("haskell-mode" . run-code--haskell-opt-command)
    ("html-mode" . "python3 -m http.server 8000")
    ("mhtml-mode" . "python3 -m http.server 8000")
    ("java-mode" . "javac % && java -server -XX:+UseG1GC -cp %:h %:t:r")
    ("js-mode" . "node %") ("js-ts-mode" . "node %")
    ("julia-mode" . "julia -O3 %")
    ("kotlin-mode" . "kotlinc % -include-runtime -d %:r.jar && java -server -jar %:r.jar")
    ("lean4-mode" . run-code--lean-check-command) ("lisp-mode" . "sbcl --script %")
    ("nim-mode" . "nim compile --opt:speed --run %")
    ("ocaml-mode" . "ocamlopt -O3 -o %:r % && ./%:r")
    ("pascal-mode" . "fpc -O3 % && ./%:r")
    ("python-mode" . (lambda () (run-code--python-command t)))
    ("python-ts-mode" . (lambda () (run-code--python-command t)))
    ("rust-mode" . "cargo run --release") ("rust-ts-mode" . "cargo run --release")
    ("scala-mode" . "scalac % && scala -J-server %:r")
    ("swift-mode" . "swiftc -O % -o %:r && ./%:r")
    ("typescript-mode" . run-code--typescript-opt-command)
    ("typescript-ts-mode" . run-code--typescript-opt-command)
    ("zig-mode" . "zig run -O ReleaseFast %")))

(defconst run-code-test-commands-default
  '(("c-mode" . "make test") ("c++-mode" . "make test")
    ("c-ts-mode" . "make test") ("c++-ts-mode" . "make test")
    ("dart-mode" . "dart test") ("go-mode" . "go test ./...")
    ("haskell-mode" . "stack test") ("java-mode" . "mvn test")
    ("js-mode" . "bun test") ("js-ts-mode" . "bun test")
    ("julia-mode" . "julia -e 'using Pkg; Pkg.test()'")
    ("kotlin-mode" . "gradle test") ("lean4-mode" . "lake test")
    ("nim-mode" . "nimble test") ("ocaml-mode" . "dune test")
    ("python-mode" . run-code--python-test-command)
    ("python-ts-mode" . run-code--python-test-command)
    ("rust-mode" . "cargo test") ("rust-ts-mode" . "cargo test")
    ("scala-mode" . "sbt test") ("swift-mode" . "swift test")
    ("typescript-mode" . "bun test") ("typescript-ts-mode" . "bun test")
    ("zig-mode" . "zig build test")))

(defun run-code--python-test-command () (run-code--python-command nil t))

(defvar run-code-language-registry nil
  "Registry of language definitions.")

(defun run-code-register-language (mode &rest properties)
  "Register MODE with PROPERTIES.
Supported properties are :dev, :opt, :test and :backend.
Commands may be strings or zero-argument functions returning strings."
  (unless (and (symbolp mode) properties (keywordp (car properties)))
    (error "Invalid language registration for %S" mode))
  (let ((entry (assq mode run-code-language-registry)))
    (if entry
        (setcdr entry properties)
      (push (cons mode properties) run-code-language-registry)))
  mode)

(defun run-code--registered-property (mode property)
  (plist-get (cdr (assq mode run-code-language-registry)) property))

(defun run-code--resolve-command-value (value)
  (if (functionp value) (funcall value) value))

(defun run-code--get-command (operation)
  (let* ((mode major-mode)
         (mode-name (symbol-name mode))
         (registered (run-code--registered-property mode (pcase operation
                                                            ('dev :dev) ('opt :opt) ('test :test))))
         (custom (if (eq operation 'test) (assoc-string mode-name run-code-test-commands)
                   (assoc-string mode-name run-code-commands)))
         (default (pcase operation
                    ('dev (assoc-string mode-name run-code-development-commands))
                    ('opt (assoc-string mode-name run-code-optimized-commands))
                    ('test (assoc-string mode-name run-code-test-commands-default)))))
    (run-code--resolve-command-value
     (or registered (cdr custom) (cdr default)))))

(defun run-code--has-command-p (mode)
  (let ((name (symbol-name mode)))
    (or (assq mode run-code-language-registry)
        (assoc-string name run-code-development-commands)
        (assoc-string name run-code-optimized-commands)
        (assoc-string name run-code-test-commands-default)
        (assoc-string name run-code-commands)
        (assoc-string name run-code-test-commands))))

(defun run-code-supported-languages ()
  "Return a sorted list of supported major-mode symbols."
  (sort (delete-dups
         (append (mapcar (lambda (x) (intern (car x))) run-code-development-commands)
                 (mapcar (lambda (x) (intern (car x))) run-code-optimized-commands)
                 (mapcar (lambda (x) (intern (car x))) run-code-test-commands-default)
                 (mapcar #'car run-code-language-registry)
                 (mapcar (lambda (x) (intern (car x))) run-code-commands)
                 (mapcar (lambda (x) (intern (car x))) run-code-test-commands)))
        (lambda (a b) (string< (symbol-name a) (symbol-name b)))))

(provide 'run-code-language)
;;; run-code-language.el ends here
