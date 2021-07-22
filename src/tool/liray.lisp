(progn ;;init forms
  (ros:ensure-asdf)
  #+quicklisp(ql:quickload '("dexador" "uiop" "cl-json") :silent t))

(defpackage :ros.script.liray
  (:use :cl))
(in-package :ros.script.liray)

(defparameter *home*  (or (uiop:getenv "ALIYA") "~/Aliya"))
(defparameter *subscribes* '())
(defparameter *servers* '())
(defparameter *lirays* '())
(defparameter *template* nil)
(defparameter *debug* nil)

(defun join-list (str list)
  (if (null list)
      ""
    (let ((result (first list)))
      (dolist (item (cdr list))
        (setf result (concatenate 'string result str item)))
      result)))

(defun split-string (string &optional (separator #\Space))
  "Return a list from a string splited at each separators"
  (loop for i = 0 then (1+ j)
        as j = (position separator string :start i)
        as sub = (subseq string i j)
        unless (string= sub "") collect sub
        while j))

(defun string->path (string)
  (let ((path (if (char= #\@ (char string 0))
                  (pathname (concatenate 'string *home* (subseq string 1)))
                  string)))
    path))

(defun load-subscribes (&optional (file (string->path "@/var/liray/subscribes.txt")))
  (let ((subscribes '()))
    (when (probe-file file)
      (dolist (url (uiop:read-file-lines file))
        (when (> (length url) 0)
          (push url subscribes))))
    (setq *subscribes* subscribes))
  (when *debug*
    (format t "Load ~A subscribes~%" (length *subscribes*)))
  *subscribes*)

(defun subscribe (url &key (cover nil) (file (string->path "@/var/liray/subscribes.txt")))
  (format t "Subscribe ~A~%" url)
  (if (position url *subscribes* :test #'equal)
      (if cover
          (setf *subscribes* (list url))
          (format t "Url ~A already subscribed...~%" url))
      (push url *subscribes*))
  (uiop:ensure-all-directories-exist (list file))
  (with-open-file (out file :direction :output :if-exists :supersede)
    (dolist (url *subscribes*)
      (format out "~A~%" url))))

(defun load-template (&optional (file (string->path "@/etc/liray/template.json")))
  (if (probe-file file)
      (let ((tmp ""))
        (with-open-file (in file)
          (with-standard-io-syntax
            (do ((line (read-line in nil) (read-line in nil)))
                ((null line) (setf *template* (json:decode-json-from-string tmp)))
              (setf tmp (concatenate 'string tmp line))))))
      (progn
        (format t "Use default")
        (setf *template*
              '((:INBOUNDS
                 ((:TAG . "socks")
                  (:PORT . 10800)
                  (:LISTEN . "127.0.0.1")
                  (:PROTOCOL . "socks")
                  (:SETTINGS (:AUTH . "noauth") (:UDP . T))
                  (:SNIFFING (:ENABLED . T) (:DEST-OVERRIDE "http" "tls")))
                 ((:TAG . "http")
                  (:PORT . 10801)
                  (:LISTEN . "127.0.0.1")
                  (:PROTOCOL . "http")
                  (:SNIFFING (:ENABLED . T) (:DEST-OVERRIDE "http" "tls"))
                  (:SETTINGS (:AUTH . "noauth") (:UDP . T))))
                (:OUTBOUNDS
                 ((:PROTOCOL . "freedom")
                  (:TAG . "direct")
                  (:SETTINGS))
                 ((:TAG . "block")
                  (:PROTOCOL . "blackhole")
                  (:SETTINGS (:VNEXT) (:SERVERS) (:RESPONSE (:TYPE . "http")))
                  (:STREAM-SETTINGS) (:MUX)))
                (:ROUTING
                 (:DOMAIN-STRATEGY . "IPOnDemand")
                 (:RULES
                  ((:TYPE . "field") (:OUTBOUND-TAG . "direct") (:DOMAIN "geosite:cn"))
                  ((:TYPE . "field") (:OUTBOUND-TAG . "direct") (:IP "geoip:cn" "geoip:private")))))))))

(defun tcping (address port &optional (timeout 3))
  (when *debug*
    (format t "Tcping ~A:~A..." address port))
  (let ((delay
          (let ((start (get-internal-real-time)))
              (handler-case
                  (progn
                    (usocket:socket-close (usocket:socket-connect address port :timeout timeout))
                    (- (get-internal-real-time) start))
                (error (condition)
                  (if (eq (type-of condition) 'usocket:timeout-error)
                     nil
                     (pprint condition)))))))
    (when *debug*
      (format t "~A~%" delay))
    delay))

(defun load-servers (&optional
                       (subscribes *subscribes*)
                       (cache (string->path "@/var/liray/servers.db"))
                       (expire 3600))
  (if (and (probe-file cache) (< (- (get-universal-time) (file-write-date cache)) expire))
      (progn
        (format t "Load servers from cache...~%")
        (with-open-file (in cache)
          (with-standard-io-syntax
            (setf *servers* (read in)))))
      (progn
        (format t "Get servers from subscribes...~%")
        (dolist (url subscribes)
          (format t "Request ~A~%" url)
          (let ((response (dex:get url)))
            (dolist (item (split-string (base64:base64-string-to-string response) #\Newline))
              (let* ((tmp (split-string item #\:))
                     (protocol (first tmp))
                     (data (json:decode-json-from-string
                            (base64:base64-string-to-string (subseq (second tmp) 2)))))
                (push (cons :p protocol) data)
                ;; (push (cons :ping (tcping (cdr (assoc :add data)) (cdr (assoc :port data)))) data)
                (push data *servers*)))))
        (uiop:ensure-all-directories-exist (list cache))
        (with-open-file (out cache :direction :output :if-exists :supersede)
          (format t "Cache servers...~%")
          (with-standard-io-syntax
            (print *servers* out))))))

(defun ping&sort ()
  (setf *servers*
        (sort
         (loop for server in *servers*
               do (push (cons :ping (tcping (cdr (assoc :add server))
                                            (cdr (assoc :port server))))
                        server)
               collect server)
         (lambda (a b) (if (numberp a)
                        (if (numberp b)
                            (< a b)
                            t)
                        nil))
         :key (lambda (a) (cdr (assoc :ping a))))))

(defun generate-config (&optional (count 6))
  (let ((template (copy-alist *template*)))
    (loop for server in (subseq *servers* 0 count)
          collect (let* ((users (list (pairlis (list :id :alter-id :security :level)
                                               (list (cdr (assoc :id server))
                                                     (cdr (assoc :aid server))
                                                     "auto"
                                                     0))))
                         (vnext (list (pairlis (list :users :port :address)
                                               (list users
                                                     (cdr (assoc :port server))
                                                     (cdr (assoc :add server))))))
                         (settings (pairlis (list :vnext :delay)
                                            (list vnext 0)))
                         (stream (pairlis (list :mux :kcp-settings :tls-settings :ws-settings :security  :network)
                                          (list (pairlis '(:enabled :concurrency) (list t 8))
                                                nil
                                                nil
                                                (if (equal (cdr (assoc :net server)) "ws")
                                                    (pairlis '(:path :headers)
                                                             (list (cdr (assoc :path server))
                                                                   (acons :-host (cdr (assoc :host server)) '())))
                                                    nil)
                                                (cdr (assoc :type server))
                                                (cdr (assoc :net server)))))
                                                
                         (outbound (pairlis (list :protocol :stream-settings :settings :tag)
                                            (list (cdr (assoc :p server))
                                                  stream
                                                  settings
                                                  (cdr (assoc :ps server))))))
                    (push outbound (cdr (assoc :outbounds template)))
                    outbound))
    template))

(defun save-config (&optional (config (generate-config))
                      (file (string->path "@/var/liray/config.json")))
  (uiop:ensure-all-directories-exist (list file))
  (with-open-file (out file :direction :output :if-exists :supersede)
    (with-standard-io-syntax
      (when *debug*
        (format t "Save config to ~A~%" file))
      (json:encode-json config out))))

(defun start (&optional (file (string->path "@/var/liray/config.json")) (output :interactive))
  (uiop:run-program (format nil "v2ray -config ~A" (namestring file))
                    :ignore-error-status t
                    :output output
                    :force-shell nil))

(defun main (&rest argv)
  (declare (ignorable argv))
  (let ((command (first argv))
        (debug (position "--debug" argv :test #'equal)))
    (when debug
      (setf *debug* t)
      (format t "Debug on..."))
    (load-subscribes)
    (load-template)
    (cond
      ((equal command "sub")
       (subscribe (second argv)))
      ((equal command "start")
       (load-servers)
       (ping&sort)
       (save-config)
       (start))
      (t
       (format t "Help~%Commands:~%  sub url ~%  start")))))

;;; vim: set ft=lisp lisp: