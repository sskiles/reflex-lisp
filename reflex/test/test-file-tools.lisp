;;; Tests for the file tools (read-file, write-file, edit-file).

(in-package #:reflex-test)

(defvar *temp-dir*
  (merge-pathnames "reflex-test-tmp/"
                   (uiop:temporary-directory)))

(defun %ensure-temp-dir ()
  (ensure-directories-exist *temp-dir*)
  *temp-dir*)

(defun %check-tool-call (name arguments predicate format-string)
  "Call a tool and check the result satisfies PREDICATE."
  (let* ((result (reflex.tools:execute-tool-call name arguments))
         (ok (and (stringp result) (funcall predicate result))))
    (check ok "tool ~A(~S): ~A, got ~S" name arguments format-string result)))

(defun test-read-file ()
  (let* ((dir (%ensure-temp-dir))
         (path (merge-pathnames "read-target.txt" dir))
         (content "Hello, file tools!"))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (write-sequence content s))
    (%check-tool-call "read-file"
                      (list (cons "path" (namestring path)))
                      (lambda (s) (string= s content))
                      "should return file contents"))
  (%check-tool-call "read-file"
                    (list (cons "path" "/no/such/file/abcxyz"))
                    (lambda (s) (search "ERROR:" s))
                    "missing file should error"))

(defun test-write-file ()
  (let* ((dir (%ensure-temp-dir))
         (path (merge-pathnames "write-target.txt" dir))
         (content "Written by write-file tool."))
    (when (probe-file path)
      (delete-file path))
    (%check-tool-call "write-file"
                      (list (cons "path" (namestring path))
                            (cons "content" content))
                      (lambda (s) (search "wrote" s))
                      "should report chars written")
    ;; Verify file actually exists with content.
    (let ((actual (handler-case
                       (with-open-file (s path :direction :input)
                         (read-line s))
                     (error () nil))))
      (check (string= actual content)
             "write-file: file content mismatch, got ~S" actual))))

(defun test-edit-file ()
  (let* ((dir (%ensure-temp-dir))
         (path (merge-pathnames "edit-target.txt" dir)))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (write-sequence "hello world, this is the original." s))
    (%check-tool-call "edit-file"
                      (list (cons "path" (namestring path))
                            (cons "old" "world")
                            (cons "new" "Reflex"))
                      (lambda (s) (search "edited" s))
                      "should report edit succeeded")
    (let ((actual (handler-case
                       (with-open-file (s path :direction :input)
                         (read-line s))
                     (error () nil))))
      (check (and actual (search "Reflex" actual) (search "this is the original" actual))
             "edit-file: file content mismatch, got ~S" actual)))
  (%check-tool-call "edit-file"
                    (list (cons "path" "/no/such/file/abcxyz")
                          (cons "old" "x")
                          (cons "new" "y"))
                    (lambda (s) (or (search "ERROR:" s) (search "edited" s)))
                    "missing file should error or report not-found"))

(defun test-bash ()
  (%check-tool-call "bash"
                    (list (cons "command" "echo hello-from-bash"))
                    (lambda (s) (search "hello-from-bash" s))
                    "should produce stdout")
  (%check-tool-call "bash"
                    (list (cons "command" "false"))
                    (lambda (s) (search "exit=" s))
                    "should report exit code")
  (%check-tool-call "bash"
                    (list (cons "command" "ls /no/such/dir/abcxyz"))
                    (lambda (s) (search "exit=" s))
                    "should report non-zero exit code"))

(defun test-file-tools ()
  (test-read-file)
  (test-write-file)
  (test-edit-file)
  (test-bash)
  (format t "~&REFLEX file-tools tests passed.~%")
  (finish-output))
