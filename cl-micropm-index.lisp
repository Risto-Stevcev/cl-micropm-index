(defpackage micropm
  (:use :cl))

(in-package :micropm)

(defvar *quicklisp-projects-dir*
  (uiop:merge-pathnames* #P"quicklisp-projects/projects/" (uiop:getcwd)))
(defvar *quicklisp-distinfo-subscription-url* "https://beta.quicklisp.org/dist/quicklisp.txt")
(defvar *index-filepath* #P"ql-index.lisp")
(setf *print-case* :downcase)

(defmacro defmemo (func-name &body body)
  "Memoizes the result of a 0-arity function"
  (let ((cached-value (gensym))
        (cached-p (gensym)))
    `(let ((,cached-value nil)
           (,cached-p nil))
       (defun ,func-name ()
         (unless ,cached-p
           (setf ,cached-value (progn ,@body))
           (setf ,cached-p t))
         ,cached-value))))

(defmemo get-system-index-url
  "Gets the latest system-index-url, a url to the latest quicklisp system index"
  (uiop:run-program (format nil
                            "curl -s ~a | grep system-index-url | cut -d' ' -f2-"
                            *quicklisp-distinfo-subscription-url*)
                    :output '(:string :stripped t)
                    :ignore-error-status t))

(defmemo get-system-index
  "Gets the system index as a string"
  (uiop:run-program
    (format nil
            "curl -s ~a | tail -n +2 | sed -e '1i(' -e '$a)' -e 's/^/(/g' -e 's/$/)/g'"
            (get-system-index-url))
    :output '(:string :stripped t)
    :ignore-error-status t))

(defmemo system-index
  "Converts the lisp string into an actual lisp object"
  (read-from-string (get-system-index)))

(defun fetch-system-quicklisp-source (system-name)
  "Fetches the quicklisp source for the given system"
  (let ((system-source
          (uiop:merge-pathnames* (format nil "~a/source.txt" (string-downcase system-name))
                                 *quicklisp-projects-dir*)))
    (map 'list (lambda (source) (uiop:split-string source :separator " "))
         (uiop:read-file-lines system-source))))

(defmemo ql-index
  "Generates a more detailed system index that includes source information"
  (loop for project in (system-index)
        when (not (member-if (lambda (e) (equal e (car project))) '(super-loader)))
        collect
        (destructuring-bind (ql-project system-file system-name &rest dependencies) project
          `(:ql-project ,ql-project :system-file ,system-file
            :system-name ,system-name :dependencies ,dependencies
            :source ,(fetch-system-quicklisp-source ql-project)))))

(defun write-index ()
  "Writes the index to the index file"
  (with-open-file (fstream *index-filepath* :direction :output)
    (write (ql-index) :stream fstream)))

(defun main ()
  (format t "Writing index...")
  (write-index)
  (format t "done.~%")
  (format t "System-index-url: ~A~%" (get-system-index-url)))

#+nil(progn
  "Load the system and build the executable"
  (pushnew (uiop:getcwd) asdf:*central-registry* :test #'equal)
  (format t "Added cwd to ASDF~%")
  (format t "Loading system...")
  (asdf:load-system "cl-micropm-index")
  (format t "done.~%")

  (format t "Building executable...")
  (asdf:make-build :cl-micropm-index
                   :type :program
                   :move-here #P"./"
                   :epilogue-code '(progn (main)
                                          (si:exit)))
  (format t "done.~%"))
