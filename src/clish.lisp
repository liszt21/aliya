(in-package :aliya)

(defun parse-params (params)
  (let ((keys '())
        (cmds '())
        (list
          (mapcar (lambda (param)
                    (if (position #\- param)
                      (intern (string-upcase (string-left-trim '(#\- ) param)) :keyword)
                      param))
                  params)))
    (dolist (item list)
      (if (keywordp item)
          (progn
            (if (keywordp (car keys))
                (push t keys))
            (push item keys))
          (progn
            (if (keywordp (car keys))
                (push item keys)
                (push item cmds)))))
    (when (keywordp (car keys))
      (push t keys))
    (setf keys (reverse keys))
    (push cmds keys)))

(defun split (string &optional (separator #\Space))
  "Return a list from a string splited at each separators"
  (loop for i = 0 then (1+ j)
        as j = (position separator string :start i)
        as sub = (subseq string i j)
        unless (string= sub "") collect sub
        while j))

(defun function-helper (fn)
  (let ((stream (make-string-output-stream)))
    (describe fn stream)
    (car (member "Lambda-list:" (split (get-output-stream-string stream) #\NewLine) :test #'search))))

(defun provide-cli (command-alist argument-list &optional (name "aliya"))
  (let* ((command (first argument-list))
         (args (parse-params (cdr argument-list)))
         (fn (cdr (assoc command command-alist :test #'equal))))
    (when (or (equal command "help") (member :help args) (not fn))
      (let ((target (if (equal command "help") (first args) command)))
        (if (member target command-alist :test #'equal :key #'car)
          (format t "~A ~A" target (function-helper fn))
          (progn
            (format t "Help for ~A~%  Commands: ~%" name)
            (dolist (item command-alist)
              (format t "    ~A ~A~%" (car item) (function-helper (cdr item)))))))
      (return-from provide-cli))
    (pprint args)
    (apply fn args)))
