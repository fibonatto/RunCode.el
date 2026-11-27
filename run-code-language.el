;;; run-code-language.el --- Language command registry -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'run-code-config)
(require 'run-code-utils)

(defvar run-code-language-registry nil
  "Alist mapping major-mode symbols to property plists.
Supported properties: :dev, :opt, :test, :font-lock.")

(defun run-code-register-language (modes &rest properties)
  "Register MODES (a symbol or list of symbols) with PROPERTIES."
  (unless (and properties (keywordp (car properties)))
    (error "Invalid language registration for %S" modes))
  (dolist (mode (if (listp modes) modes (list modes)))
    (unless (symbolp mode)
      (error "Mode must be a symbol: %S" mode))
    (let ((entry (assq mode run-code-language-registry)))
      (if entry
          (setcdr entry properties)
        (push (cons mode properties) run-code-language-registry))))
  modes)

(defun run-code--registered-property (mode property)
  (plist-get (cdr (assq mode run-code-language-registry)) property))

(defun run-code--resolve-command-value (value)
  (if (functionp value) (funcall value) value))

(defun run-code--get-command (operation)
  (let* ((mode major-mode)
         (prop (pcase operation
                 ('dev :dev)
                 ('opt :opt)
                 ('test :test)))
         (custom (if (eq operation 'test)
                     (alist-get mode run-code-test-commands)
                   (alist-get mode run-code-commands)))
         (registered (run-code--registered-property mode prop)))
    (run-code--resolve-command-value (or custom registered))))

(defun run-code--has-command-p (mode)
  (or (assq mode run-code-language-registry)
      (assq mode run-code-commands)
      (assq mode run-code-test-commands)))

(defun run-code-supported-languages ()
  "Return a sorted list of supported major-mode symbols."
  (sort (delete-dups
         (append (mapcar #'car run-code-language-registry)
                 (mapcar #'car run-code-commands)
                 (mapcar #'car run-code-test-commands)))
        (lambda (a b) (string< (symbol-name a) (symbol-name b)))))

;;; Project & Environment Helpers

(defun run-code--project-root-p (&rest markers)
  "Return dominating directory containing any file in MARKERS."
  (locate-dominating-file
   (run-code--file-directory)
   (lambda (dir)
     (cl-some (lambda (m) (file-readable-p (expand-file-name m dir)))
              markers))))

(defun run-code--temp-binary ()
  "Return a unique temporary executable path in `run-code-temp-dir'."
  (shell-quote-argument
   (expand-file-name (format "run-code-%d" (emacs-pid)) run-code-temp-dir)))

;;; Language Command Builders

(defun run-code--c-command (&optional optimized)
  (if (run-code--project-root-p "Makefile" "makefile" "GNUmakefile")
      (if optimized "make" "make run")
    (let ((bin (run-code--temp-binary))
          (flags (if optimized "-O2 -Wall -Wextra" "-O0 -g -Wall -Wextra")))
      (format "clang %s %% -o %s && %s; rc=$?; rm -f %s; exit $rc"
              flags bin bin bin))))

(defun run-code--cpp-command (&optional optimized)
  (if (run-code--project-root-p "Makefile" "makefile" "GNUmakefile")
      (if optimized "make" "make run")
    (let ((bin (run-code--temp-binary))
          (flags (if optimized "-std=c++17 -O2 -Wall -Wextra" "-std=c++17 -O0 -g -Wall -Wextra"))
          (llvm (if (string-match-p "#include[[:space:]]*[<\\\"]llvm/" (run-code--buffer-text))
                    " $(llvm-config --cxxflags --ldflags --system-libs --libs all)"
                  "")))
      (format "clang++ %s %%%s -o %s && %s; rc=$?; rm -f %s; exit $rc"
              flags llvm bin bin bin))))

(defun run-code--rust-command (&optional optimized)
  (if (run-code--project-root-p "Cargo.toml")
      (if optimized "cargo run --release" "cargo run")
    (let ((bin (run-code--temp-binary))
          (flags (if optimized "-O" "-g")))
      (format "rustc %s %% -o %s && %s; rc=$?; rm -f %s; exit $rc"
              flags bin bin bin))))

(defun run-code--haskell-command (&optional optimized)
  (cond
   ((run-code--project-root-p "stack.yaml")
    (if optimized "stack run --ghc-options=-O2" "stack run"))
   ((run-code--project-root-p "package.yaml")
    (if optimized "cabal run -O2" "cabal run"))
   (t
    (let ((bin (run-code--temp-binary))
          (dir (shell-quote-argument run-code-temp-dir))
          (flags (if optimized "-O2 -threaded" "-O0")))
      (format "ghc %s -outputdir %s %% -o %s && %s; rc=$?; rm -f %s; exit $rc"
              flags dir bin bin bin)))))

(defun run-code--typescript-opt-command ()
  (let ((dir (shell-quote-argument run-code-temp-dir)))
    (format "tsc %% --outDir %s && node %s/%%:t:r.js" dir dir)))

(defun run-code--python-venv-executable (directory)
  (cl-loop for exe in '("python" "python3")
           for path = (expand-file-name (concat "bin/" exe) directory)
           when (file-executable-p path) return path))

(defun run-code--find-project-python-venv ()
  (let ((dir (file-name-as-directory (expand-file-name (run-code--file-directory))))
        found)
    (while (and dir (not found))
      (setq found
            (cl-loop for name in run-code-python-venv-directories
                     for path = (expand-file-name name dir)
                     when (file-directory-p path)
                     thereis (run-code--python-venv-executable path)))
      (unless found
        (let ((parent (file-name-directory (directory-file-name dir))))
          (setq dir (unless (or (null parent) (equal parent directory)) parent)))))
    found))

(defun run-code--python-executable ()
  (let* ((venv (getenv "VIRTUAL_ENV"))
         (active (and venv (file-directory-p venv)
                      (run-code--python-venv-executable venv))))
    (or active
        (run-code--find-project-python-venv)
        (executable-find "python3")
        (executable-find "python")
        (user-error "Python interpreter not found"))))

(defun run-code--python-command (&optional mode)
  (concat (shell-quote-argument (run-code--python-executable))
          (pcase mode
            ('test " -m pytest")
            ('opt  " -O %")
            (_     " -u %"))))

(defun run-code--lean-check-command ()
  "Check Lean types and display categorized local declarations."
  (let ((lean-cmd (if (run-code--project-root-p "lakefile.lean" "lakefile.toml")
                      "lake env lean"
                    "lean")))
    (concat
     "tmpdir=$(mktemp -d \"%:h/.run-code.XXXXXX\") || exit 1\n"
     "tmp=\"$tmpdir/Context.lean\"\n"
     "trap 'rm -rf \"$tmpdir\"' EXIT\n"
     "{ echo 'import Lean'; cat %; } > \"$tmp\" || exit 1\n"
     "cat >> \"$tmp\" <<'RUN_CODE_LEAN_CONTEXT'\n\n"
     "open Lean Elab Command Meta\n\n"
     "run_cmd do\n"
     "  let isInternal (name : Name) : Bool := Id.run do\n"
     "    let s := name.toString\n"
     "    let last := (s.splitOn \".\").getLast!\n"
     "    last ∈ [\"rec\", \"casesOn\", \"recOn\", \"brecOn\", \"binductionOn\",\n"
     "            \"below\", \"ibelow\", \"noConfusion\", \"noConfusionType\",\n"
     "            \"ctorIdx\", \"ctorElim\", \"ctorElimType\", \"elim\",\n"
     "            \"inj\", \"injEq\", \"sizeOf_spec\", \"_f\", \"_unsafe_rec\", \"_sunfold\"] ||\n"
     "    last.startsWith \"match_\" || last.startsWith \"eq_\" || last.startsWith \"proof_\" ||\n"
     "    s.contains \".brecOn.\" || s.contains \".below.\" || s.contains \".ibelow.\" || s.contains \"._\"\n\n"
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
     "      | _ => return .continue\n\n"
     "  let renderDecl (header : String) (fmt : Format) (maxW : Nat := 60) : MessageData :=\n"
     "    let single := fmt.pretty (width := maxW) (indent := 2) (column := header.length + 1)\n"
     "    if single.contains '\\n' || header.length + 1 + single.length > maxW then\n"
     "      let multi := fmt.pretty (width := maxW) (indent := 2) (column := 2)\n"
     "      MessageData.ofFormat (Format.text s!\"{header}\\n  {multi}\")\n"
     "    else\n"
     "      MessageData.ofFormat (Format.text s!\"{header} {single}\")\n\n"
     "  let env ← getEnv\n"
     "  let infos ← liftIO <| env.getLocalConstantInfos (skipTheoremSubDecls := true)\n"
     "  let mut propDefs : NameSet := {}\n"
     "  for info in infos do\n"
     "    unless isInternal info.name do\n"
     "      if let .defnInfo val := info.toConstantInfo then\n"
     "        if val.type == Expr.sort Level.zero && val.safety != .partial then\n"
     "          propDefs := propDefs.insert info.name\n\n"
     "  let mut thms : Array MessageData := #[]\n"
     "  let mut openGoals : Array MessageData := #[]\n"
     "  let mut ctors : Array MessageData := #[]\n"
     "  let mut defs : Array MessageData := #[]\n"
     "  let mut axioms : Array MessageData := #[]\n\n"
     "  for info in infos do\n"
     "    unless isInternal info.name do\n"
     "      match info.toConstantInfo with\n"
     "      | .thmInfo val =>\n"
     "        let msg ← liftTermElabM do\n"
     "          let ty ← Core.betaReduce (← unfoldProps propDefs val.type)\n"
     "          let fmt ← ppExpr ty\n"
     "          let header := if val.value.hasSorry then s!\"sorry {info.name} :\" else s!\"theorem {info.name} :\"\n"
     "          pure (renderDecl header fmt)\n"
     "        if val.value.hasSorry then openGoals := openGoals.push msg else thms := thms.push msg\n"
     "      | .ctorInfo val =>\n"
     "        let msg ← liftTermElabM do\n"
     "          let ty ← Core.betaReduce (← unfoldProps propDefs val.type)\n"
     "          pure (renderDecl s!\"ctor {info.name} :\" (← ppExpr ty))\n"
     "        ctors := ctors.push msg\n"
     "      | .defnInfo val =>\n"
     "        unless propDefs.contains info.name do\n"
     "          let last := (info.name.toString.splitOn \".\").getLast!\n"
     "          unless last.endsWith \"Aux\" || last.endsWith \"_aux\" do\n"
     "            let msg ← liftTermElabM do\n"
     "              pure (renderDecl s!\"def {info.name} :\" (← ppExpr val.type))\n"
     "            defs := defs.push msg\n"
     "      | .axiomInfo val =>\n"
     "        let msg ← liftTermElabM do\n"
     "          let ty ← Core.betaReduce (← unfoldProps propDefs val.type)\n"
     "          pure (renderDecl s!\"axiom {info.name} :\" (← ppExpr ty))\n"
     "        axioms := axioms.push msg\n"
     "      | .opaqueInfo val =>\n"
     "        let msg ← liftTermElabM do\n"
     "          let ty ← Core.betaReduce (← unfoldProps propDefs val.type)\n"
     "          pure (renderDecl s!\"opaque {info.name} :\" (← ppExpr ty))\n"
     "        axioms := axioms.push msg\n"
     "      | _ => pure ()\n\n"
     "  let logSection (title : String) (items : Array MessageData) : CommandElabM Unit := do\n"
     "    unless items.isEmpty do\n"
     "      logInfo m!\"── {title} ──\\n{MessageData.joinSep items.toList m!\"\\n\"}\"\n\n"
     "  logSection \"THEOREMS\" thms\n"
     "  logSection \"CONSTRUCTORS\" ctors\n"
     "  logSection \"OPEN GOALS (sorry)\" openGoals\n"
     "  logSection \"AXIOMS / OPAQUE\" axioms\n"
     "  logSection \"DEFINITIONS\" defs\n\n"
     "  let activeVars ← runTermElabM fun xs => do\n"
     "    let mut vars : Array MessageData := #[]\n"
     "    for x in xs do\n"
     "      vars := vars.push m!\"variable {← ppExpr x} : {← ppExpr (← inferType x)}\"\n"
     "    pure vars\n"
     "  logSection \"ACTIVE VARIABLES\" activeVars\n"
     "RUN_CODE_LEAN_CONTEXT\n"
     lean-cmd " \"$tmp\"")))

;;; Language Registrations

;; Primary languages
(run-code-register-language
 '(c-mode c-ts-mode)
 :dev  (lambda () (run-code--c-command nil))
 :opt  (lambda () (run-code--c-command t))
 :test "make test")

(run-code-register-language
 '(c++-mode c++-ts-mode)
 :dev  (lambda () (run-code--cpp-command nil))
 :opt  (lambda () (run-code--cpp-command t))
 :test "make test")

(run-code-register-language
 '(rust-mode rust-ts-mode)
 :dev  (lambda () (run-code--rust-command nil))
 :opt  (lambda () (run-code--rust-command t))
 :test "cargo test"
 :font-lock 'run-code--rust-font-lock-keywords)

(run-code-register-language
 '(haskell-mode haskell-ts-mode)
 :dev  (lambda () (run-code--haskell-command nil))
 :opt  (lambda () (run-code--haskell-command t))
 :test "stack test")

(run-code-register-language
 '(js-mode js-ts-mode)
 :dev  "bun run %"
 :opt  "node %"
 :test "bun test")

(run-code-register-language
 '(typescript-mode typescript-ts-mode)
 :dev  "bun run %"
 :opt  #'run-code--typescript-opt-command
 :test "bun test")

(run-code-register-language
 '(python-mode python-ts-mode)
 :dev  (lambda () (run-code--python-command 'dev))
 :opt  (lambda () (run-code--python-command 'opt))
 :test (lambda () (run-code--python-command 'test))
 :font-lock 'run-code--python-font-lock-keywords)

(run-code-register-language
 'agda-mode
 :dev  "agda-cli check %"
 :opt  "agda-cli run %"
 :font-lock 'run-code--agda-font-lock-keywords)

(run-code-register-language
 'lean4-mode
 :dev  #'run-code--lean-check-command
 :opt  #'run-code--lean-check-command
 :test "lake test"
 :font-lock 'run-code--lean-font-lock-keywords)

;; Additional languages
(run-code-register-language 'bend-mode    :dev "bend %" :opt "bend %")
(run-code-register-language 'caramel-mode :dev "mel main")
(run-code-register-language 'coc-mode     :dev "coc type %:r && coc norm %:r")
(run-code-register-language 'csharp-mode  :dev "mcs % -out:%:r.exe && mono %:r.exe")
(run-code-register-language 'cuda-mode    :dev "nvcc % -o %:r && ./%:r" :opt "nvcc -O3 % -o %:r && ./%:r")
(run-code-register-language 'dart-mode    :dev "dart %" :opt "dart compile exe % -o %:r && ./%:r" :test "dart test")
(run-code-register-language 'dvl-mode     :dev "dvl run %")
(run-code-register-language 'elm-mode     :dev "elm make % --output=%:r.js")
(run-code-register-language 'erlang-mode  :dev "escript %")
(run-code-register-language 'go-mode      :dev "go run %" :opt "go build -ldflags=\"-s -w\" -o %:r % && ./%:r" :test "go test ./...")
(run-code-register-language '(html-mode mhtml-mode) :dev "npm run dev" :opt "python3 -m http.server 8000")
(run-code-register-language 'web-mode     :dev "npm run dev")
(run-code-register-language 'http-mode    :dev "httpyac --all route.http")
(run-code-register-language 'java-mode    :dev "javac % && java -cp %:h %:t:r" :opt "javac % && java -server -XX:+UseG1GC -cp %:h %:t:r" :test "mvn test")
(run-code-register-language 'julia-mode   :dev "julia %" :opt "julia -O3 %" :test "julia -e 'using Pkg; Pkg.test()'")
(run-code-register-language 'kotlin-mode  :dev "kotlinc % -include-runtime -d %:r.jar && java -jar %:r.jar" :opt "kotlinc % -include-runtime -d %:r.jar && java -server -jar %:r.jar" :test "gradle test")
(run-code-register-language 'lisp-mode    :dev "sbcl --script %" :opt "sbcl --script %")
(run-code-register-language 'lua-mode     :dev "lua %")
(run-code-register-language 'nim-mode     :dev "nim compile --run %" :opt "nim compile --opt:speed --run %" :test "nimble test")
(run-code-register-language 'ocaml-mode   :dev "ocamlc -o %:r % && ./%:r" :opt "ocamlopt -O3 -o %:r % && ./%:r" :test "dune test")
(run-code-register-language 'pascal-mode  :opt "fpc -O3 % && ./%:r")
(run-code-register-language 'perl-mode    :dev "perl -w %")
(run-code-register-language 'php-mode     :dev "php %")
(run-code-register-language 'r-mode       :dev "Rscript %")
(run-code-register-language 'ruby-mode    :dev "ruby %")
(run-code-register-language 'scala-mode   :dev "scala %" :opt "scalac % && scala -J-server %:r" :test "sbt test")
(run-code-register-language 'scheme-mode  :dev "csc % && ./%:r")
(run-code-register-language 'sh-mode      :dev "bash -x %")
(run-code-register-language 'swift-mode   :dev "swift %" :opt "swiftc -O % -o %:r && ./%:r" :test "swift test")
(run-code-register-language 'zig-mode     :dev "zig run %" :opt "zig run -O ReleaseFast %" :test "zig build test")

(provide 'run-code-language)
;;; run-code-language.el ends here
