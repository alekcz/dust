(require dust.project :as p)
(refer 'dust.project :only '(defproject load-project!))

(require dust.deps :as d)
(require pixie.string :as str)
(require pixie.io :as io)
(require pixie.fs :as fs)
(require pixie.test :as t)
(require pixie.io.tty :as tty)
(require pixie.string :as s)

(def *all-commands* (atom {}))
(def unknown-command (atom true))
(def show-all (atom false))
(def namespaces (atom '("pixie.stdlib"  "pixie.async" "pixie.math" "pixie.stacklets" "pixie.system" "pixie.buffers" "pixie.test" "pixie.channels" "pixie.parser" "pixie.time" "pixie.csp" "pixie.uv" "pixie.repl" "pixie.streams" "pixie.ffi-infer" "pixie.io.common" "pixie.io.tty" "pixie.io.tcp" "pixie.io.uv-common" "pixie.io" "pixie.io-blocking" "pixie.fs" "pixie.set" "pixie.string" "pixie.walk")))


(defmacro defcmd
  [name description params & body]
  (let [body (if (:no-project (meta name))
               body
               (cons `(load-project!) body))
        cmd {:name (str name)
             :description description
             :params `(quote ~params)
             :cmd (cons `fn (cons params body))}]
    `(do (swap! *all-commands* assoc '~name ~cmd)
         '~name)))

(defcmd describe
  "Describe the current project."
  []
  (p/describe @p/*project*))


(defn showdoc [ns function]
  (let [name (str (if (= function "/") (str  ns) (str ns "/")))]
  ;loads other possible namespaces in case function is in other namespace
    (if (= @show-all true) (eval   (read-string (str "(require " ns ")"))))
      
    (let [data (meta (eval (read-string (str name function)))) func-name (if (and (not= (str/index-of function "/") nil) (not= (str function) "/")) (str function) (str name function))]
      (print (str "\n  " func-name "\n\n\t"))
      (loop [sigs (lazy-seq (:signatures data))]
        (when (not= sigs '()) 
          (print (str/replace (str (lazy-seq (first sigs)) "  ") "(" (str "(" func-name " ")))
          (recur (rest sigs))))

      (if (nil? data)
        (do 
          (println "\n\n\t No documentation available.\n")
          (reset! unknown-command false)
          (if (= (first @namespaces) "") (reset! namespaces '())))
        (do
          (print (str "\n\n\t"))
          (print
            (if (not= (str (:doc data)) "nil") 
                (str (:doc data) " ")
                (str "No further documentation available.\n")))
          (reset! unknown-command false)
          (print 
            (if (not= (str (:added data)) "nil") 
                (str " [added: v" (:added data) "]\n\n") 
                (str "\n\n")))
          (if (= (first @namespaces) "pixie.stdlib")
            (reset! namespaces '())))))))



(defcmd ^:no-project doc
  "Show function documentation. Broaden search using -all"
 [ & args]
   (if (empty? args)
    (help-cmd "doc")
    (let [function-name (first args) search-all (first (rest args))]
      (if (and (not= (str/index-of (str function-name) "/") nil) (not= (str function-name) "/") )
          ;test for division operator as function to be documented
          (do
            (try 
              (eval (read-string (str "(require " (str/substring function-name 0 (str/index-of function-name "/")) ")")))
              ;load the required namespaces

              (showdoc (str (first @namespaces)) (str function-name))
              (catch e
               (reset! unknown-command true)))
              (reset! namespaces '())))
      (if (= (str search-all) "-all") (reset! show-all true))
      (loop [_ 0]
        (when (not= @namespaces '()) 
          (try (showdoc (str (first @namespaces)) (if (= function-name "deps") (str "*") (str function-name)))
            ; $ dust doc * -> dust doc deps ???
            (catch e
             nil)) 
             (recur (reset! namespaces (rest @namespaces)))))
      (if (= @unknown-command true) (println (str "\n  " function-name "\n\n\t Function not found. " (if (not= (str search-all) "-all") (str "Broaden search using -all flag.\n") (str "\n"))))))))

(defcmd deps
  "List the dependencies and their versions of the current project."
  []
  (doseq [[name version] (:dependencies @p/*project*)]
    (println name version)))

(defcmd load-path
  "Print the load path of the current project."
  []
  (when (not (fs/exists? (fs/file ".load-path")))
    (println "Please run `dust get-deps`")
    (exit 1))
  (doseq [path (str/split (io/slurp ".load-path") "--load-path")]
    (when (not (str/empty? path))
      (println (str/trim path)))))

(defcmd get-deps
  "Download the dependencies of the current project."
  []
  (-> @p/*project* d/get-deps d/write-load-path))

(defcmd ^:no-project repl
  "Start a REPL in the current project."
  []
  (throw (str "This should be invoked by the wrapper.")))

(defcmd ^:no-project run
  "Run the code in the given file."
  [file]
  (throw (str "This should be invoked by the wrapper.")))

(defn load-tests [dirs]
  (println "Looking for tests...")
  (let [dirs (distinct (map fs/dir dirs))
        pxi-files (->> dirs
                       (mapcat fs/walk-files)
                       (filter #(fs/extension? % "pxi"))
                       (filter #(str/starts-with? (fs/basename %) "test-"))
                       (distinct))]
    (foreach [file pxi-files]
             (println "Loading " file)
             (load-file (fs/abs file)))))

(defcmd test "Run the tests of the current project."
  [& args]
  (println @load-paths)

  (load-tests (:test-paths @p/*project*))

  (let [result (apply t/run-tests args)]
    (exit (get result :fail))))

(defn help-cmd [cmd]
  (let [{:keys [name description params] :as info} (get @*all-commands* (symbol cmd))]
    (if info
      (do
        (println (str "Usage: dust " name " " params))
        (println)
        (println description))
      (println "Unknown command:" cmd))))

(defn help-all []
  (println "Usage: dust <cmd> <options>")
  (println)
  (println "Available commands:")
  (doseq [{:keys [name description]} (vals @*all-commands*)]
    (println (str "  " name (apply str (repeat (- 10 (count name)) " ")) description))))

(defcmd ^:no-project help
  "Display the help"
  [& [cmd]]
  (if cmd
    (help-cmd cmd)
    (help-all)))

(defcmd ^:no-project init
  "Initialize new Pixie project"
 [ & args]
   (if (empty? args)
    (help-cmd "init")
    (let [project-name (first args) config-default (first (rest args)) entry (atom "core.pxi") version (atom "0.0.1") description (atom "A Pixie project") repo (atom "")]
      (println (str "Initializing " project-name "..."))

      (d/mkdir (str project-name "/src/" project-name))
      (d/mkdir (str project-name "/test/" project-name "/test"))
      ;(println config-default)
      (io/spit (str project-name "/src/" project-name "/" @entry) (str "(ns " project-name "." (s/substring @entry 0 (s/index-of @entry "."))")"))
      
      (io/spit (str project-name "/test/" project-name "/test/test-" @entry)
        (str "(ns " project-name ".test-" (s/substring @entry 0 (s/index-of @entry ".")) "
        (:require [pixie.test :refer [deftest assert assert-throws?]]
                  [" (s/substring @entry 0 (s/index-of @entry ".")) ":refer :all]))
;;pixie doesnt have testing yet...
(defn testing [text & body])

(def is assert)
(deftest test-name
  (testing \"a function\"
    (is (= true true))
    (is (= true (not false)))
    (is (= true (not (not true))))))"))

      (io/spit (str project-name "/project.edn") (str "{:name " project-name " \n:version \"" @version "\" \n:description \"" @description "\" \n:dependencies [] \n:repo \"" @repo"\"}\n"))
      

      
     (println "Initialization complete"))))



(def *command* (first program-arguments))

(let [cmd (get @*all-commands* (symbol *command*))]
  (try
    (if cmd
      (apply (get cmd :cmd) (next program-arguments))
      (println "Unknown command:" *command*))
    (catch :dust/Exception e
      (println (str "Dust encountered an error: " (pr-str (ex-msg e)))))))
