(in-package :clish)

(defun splice (list index &optional (remove 1) (insert '()))
  (if index
      (append
       (subseq list 0 (min index (length list)))
       insert
       (subseq list (min (length list) (max 1 (+ index remove)))))
      list))

;; (defun parse-content (text)
;;   (let* ((lines (str:split #\NewLine text))
;;          (parents (list (list))))
;;     (dolist (line lines)
;;       (let ((section (parse-section line))
;;             (end? (str:containsp "END" line)))
;;         (print parents)
;;         (if section
;;             (if end?
;;                 (push (nreverse (pop parents)) (car parents))
;;                 (push (list section) parents))
;;             (push line (car parents)))))
;;     (nreverse (car parents))))

(defun generate-alias-define (name command &optional directory)
  (format nil
          "function ~A {~%~A  ~A ~A;~A~%}"
          name
          (if directory (format nil "  ~Acd ~A;~%" #+os-windows "$OLDPWD=pwd;" #-os-windows "" directory) "")
          command
          #+os-windows "$args" #-os-windows "\"$@\""
          (if directory (format nil "~%  cd $OLDPWD;") "")))

(defmacro maintain-entry (&key insert remove)
    `(with-profile (ctx :section "clish"
                        :module
                        #+os-windows "profile"
                        #-os-windows #+zsh "zsh" #-(or zsh) "bash"
                        :remove-if-empty nil)
        ,(when remove
          `(let ((index (position ,remove ctx :test #'equal)))
            (when index (setf ctx (splice ctx index)))))

        (setf ctx
            (loop for line in ctx
                  while (or (not (str:starts-with-p #+os-windows ". " #-os-windows "source " line))
                            (probe-file (subseq line #+os-windows 2 #-os-windows 7)))
                  collect line))

        ,(when insert
            `(when (not (position ,insert ctx :test #'equal))
                (setf ctx (append ctx (list ,insert)))))))

(defmacro with-profile ((ref &key section (module "clish") (remove-if-empty t)) &body body)
  (let* ((path (concatenate 'string "~/"
                            #+os-windows "Documents/WindowsPowerShell/"
                            #+os-windows (format nil "~A.ps1" (string-capitalize module))
                            #-os-windows (format nil ".~Arc" module)))
         (text (if (probe-file path)
                   (str:from-file path)
                   (format nil "#---Module ~A auto generated by clish---~%" module)))
         (content (str:split #\NewLine text))
         (content-length (length content))
         (begin-mark (and section (format nil "#+~A_BEGIN" (string-upcase section))))
         (end-mark (and section (format nil "#+~A_END" (string-upcase section))))
         (begin (if section (position begin-mark content :test #'equal) 0))
         (end (if (and section begin) (position end-mark content :test #'equal :start begin) content-length)))

    ;; (when (null (position module '("bash" "zsh" "fish" "profile") :test #'equal))
    ;;   (maintain-entry :insert (format nil "~A ~A" #+os-windows "." #-os-windows "source" path)))

    `(let ((,ref (list ,@(if (and section begin) (subseq content (+ begin 1) end) content))))
        ,@body
        (with-open-file (out ,path :direction :output :if-exists :supersede)
          (princ (str:join #\NewLine
                          (splice (list ,@content)
                                  ,(or begin content-length)
                                  ,(or (and begin end (- end begin -1)) content-length)
                                  (and ,ref
                                        (append ,(if begin-mark `(list ,begin-mark))
                                                ,ref
                                                ,(if end-mark `(list ,end-mark)))))) out))
        ,(when (and (not section) remove-if-empty)
          `(when (or (null ,ref) (zerop (length ,ref)))
                (maintain-entry :remove ,(format nil "~A ~A" #+os-windows "." #-os-windows "source" path)))))))

