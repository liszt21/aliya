(defun detect-asd-files ()
    (directory #p"../systems/**/*.asd"))

(defun load-asd-files (files)
    (loop for file in files
          do (asdf:load-asd file)))

(load-asd-files (detect-asd-files))

(defsystem "aliya"
  :version "0.1.0"
  :author "Liszt21"
  :license ""
  :depends-on ("likit" "clish" "emacy" "ust" "loong")
  :serial t
  :components ((:module "src"
                        :components
                        ((:file "main"))))
  :entry-point "aliya:cli"
  :description "Liszt's virtual assistant"
  :in-order-to ((test-op (test-op "aliya/tests"))))

(defsystem "aliya/tests"
  :author "Liszt21"
  :license ""
  :depends-on ("aliya"
               "fiveam")
  :components ((:module "tests"
                :components
                ((:file "main"))))
  :description "Test system for aliya"
  :perform (test-op (op c) (symbol-call :fiveam :run! :aliya)))
