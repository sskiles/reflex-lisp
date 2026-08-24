;;;; harness/stage-4/tools.lisp - Standard tools (Stage 4)

(defpackage #:harness.stage-4.tools
  (:use #:cl #:harness.tools.protocol #:harness.tools.registry #:harness.stage-0.protocol #:harness.stage-1.protocol)
  (:export #:register-standard-tools
           #:make-bash-tool
           #:make-read-file-tool
           #:make-write-file-tool
           #:make-edit-file-tool
           #:make-save-image-tool
           #:make-query-tool
           #:make-refresh-model-list-tool
           #:make-model-tool
           #:register-tool-fn
           #:default-registry))

(in-package #:harness.stage-4.tools)

;;; --- Helpers (matches original tools-*.lisp) -------------------------------

(defun read-file-as-string (path)
  (handler-case
      (with-open-file (stream path :direction :input)
        (let ((contents (make-string (file-length stream))))
          (read-sequence contents stream)
          contents))
    (error (e) (format nil "Error reading ~A: ~A" path e))))

(defun write-string-to-file (path content)
  (handler-case
      (with-open-file (stream path :direction :output :if-exists :supersede)
        (write-sequence content stream)
        (format nil "Wrote ~A bytes to ~A" (length content) path))
    (error (e) (format nil "Error writing ~A: ~A" path e))))

(defun replace-all (string old new)
  (let ((pos (search old string)))
    (if pos
        (concatenate 'string
                     (subseq string 0 pos)
                     new
                     (replace-all (subseq string (+ pos (length old))) old new))
        string)))

(defun make-edit (path old new)
  (let ((content (read-file-as-string path)))
    (if (search old content)
        (write-string-to-file path (replace-all content old new))
        (format nil "String not found in ~A: ~A" path old))))

;;; --- Bash Tool -------------------------------------------------------------

(defun make-bash-tool ()
  (make-tool-spec
   "bash"
   "Execute a shell command and return stdout/stderr."
   (plist-to-hash '("type" "object"
                    "properties" ("command" ("type" "string")
                                  "timeout" ("type" "integer" "default" 30))
                    "required" ("command")
                    "additionalProperties" nil))
   (lambda (args)
     (let ((cmd (cond
                  ((typep args 'hash-table)
                   (or (gethash "command" args) (gethash "cmd" args)))
                  ((listp args)
                   (cdr (or (assoc "command" args :test #'string=)
                            (assoc "cmd" args :test #'string=)))))))
       (if (not (stringp cmd))
           (values nil "Error: Missing string argument 'command'")
           (handler-case
               (multiple-value-bind (output error-output exit-code)
                   (uiop:run-program cmd :output '(:string :stripped t)
                                         :error-output '(:string :stripped t)
                                         :ignore-error-status t)
                 (let ((res (format nil "~@[~A~%~]~@[~A~%~][exit code: ~A]"
                                    (unless (string= output "") output)
                                    (unless (string= error-output "") error-output)
                                    exit-code)))
                   (values res nil)))
             (error (e)
               (values nil (format nil "Bash error: ~A" e)))))))))

;;; --- Read File Tool --------------------------------------------------------

(defun make-read-file-tool ()
  (make-tool-spec
   "read-file"
   "Read a file's contents as text."
   (plist-to-hash '("type" "object"
                    "properties" ("path" ("type" "string"))
                    "required" ("path")
                    "additionalProperties" nil))
   (lambda (args)
     (let ((path (cond
                   ((typep args 'hash-table)
                    (or (gethash "path" args)
                        (gethash "filename" args)
                        (gethash "file" args)))
                   ((listp args)
                    (cdr (or (assoc "path" args :test #'string=)
                             (assoc "filename" args :test #'string=)
                             (assoc "file" args :test #'string=)))))))
       (if (not (stringp path))
           (values nil "Error: Missing string argument 'path'")
           (handler-case
               (let ((content (uiop:read-file-string path)))
                 (values content nil))
             (error (e)
               (values nil (format nil "Error reading ~A: ~A" path e)))))))))

;;; --- Write File Tool -------------------------------------------------------

(defun make-write-file-tool ()
  (make-tool-spec
   "write-file"
   "Create or overwrite a file with the given content."
   (plist-to-hash '("type" "object"
                    "properties" ("path" ("type" "string")
                                  "content" ("type" "string"))
                    "required" ("path" "content")
                    "additionalProperties" nil))
   (lambda (args)
     (let ((path (cond
                   ((typep args 'hash-table)
                    (or (gethash "path" args) (gethash "filename" args)))
                   ((listp args)
                    (cdr (or (assoc "path" args :test #'string=)
                             (assoc "filename" args :test #'string=))))))
           (content (cond
                      ((typep args 'hash-table)
                       (or (gethash "content" args) (gethash "text" args) (gethash "data" args)))
                      ((listp args)
                       (cdr (or (assoc "content" args :test #'string=)
                                (assoc "text" args :test #'string=)
                                (assoc "data" args :test #'string=)))))))
       (cond
         ((not (stringp path)) (values nil "Error: Missing string argument 'path'"))
         ((not (stringp content)) (values nil "Error: Missing string argument 'content'"))
         (t (handler-case
                (progn
                  (ensure-directories-exist path)
                  (with-open-file (stream path :direction :output :if-exists :supersede :if-does-not-exist :create)
                    (write-sequence content stream))
                  (values (format nil "Successfully wrote ~A bytes to ~A" (length content) path) nil))
              (error (e)
                (values nil (format nil "Error writing ~A: ~A" path e))))))))))

;;; --- Edit File Tool --------------------------------------------------------

(defun make-edit-file-tool ()
  (make-tool-spec
   "edit-file"
   "Make exact string replacements in a file."
   (plist-to-hash '("type" "object"
                    "properties" ("path" ("type" "string")
                                  "old" ("type" "string")
                                  "new" ("type" "string"))
                    "required" ("path" "old" "new")
                    "additionalProperties" nil))
   (lambda (args)
     (let ((path (cond
                   ((typep args 'hash-table) (gethash "path" args))
                   ((listp args) (cdr (assoc "path" args :test #'string=)))))
           (old (cond
                  ((typep args 'hash-table) (or (gethash "old" args) (gethash "old_string" args)))
                  ((listp args) (cdr (or (assoc "old" args :test #'string=)
                                         (assoc "old_string" args :test #'string=))))))
           (new (cond
                  ((typep args 'hash-table) (or (gethash "new" args) (gethash "new_string" args)))
                  ((listp args) (cdr (or (assoc "new" args :test #'string=)
                                         (assoc "new_string" args :test #'string=)))))))
       (cond
         ((not (stringp path)) (values nil "Error: Missing string argument 'path'"))
         ((not (stringp old)) (values nil "Error: Missing string argument 'old'"))
         ((not (stringp new)) (values nil "Error: Missing string argument 'new'"))
         (t (handler-case
                (let ((content (uiop:read-file-string path)))
                  (if (not (search old content))
                      (values nil (format nil "String not found in ~A: ~S" path old))
                      (let ((updated (replace-all content old new)))
                        (with-open-file (stream path :direction :output :if-exists :supersede)
                          (write-sequence updated stream))
                        (values (format nil "Successfully updated ~A" path) nil))))
              (error (e)
                (values nil (format nil "Error editing ~A: ~A" path e))))))))))

;;; --- Save Image Tool -------------------------------------------------------

(defun make-save-image-tool ()
  (make-tool-spec
   "save-image"
   "Save the current Lisp image to a core file."
   (plist-to-hash '("type" "object"
                    "properties" ("path" ("type" "string"))
                    "required" ("path")
                    "additionalProperties" nil))
   (lambda (args)
     (let ((path (cond
                   ((typep args 'hash-table) (gethash "path" args))
                   ((listp args) (cdr (assoc "path" args :test #'string=))))))
       (if (not (stringp path))
           (values nil "Error: Missing string argument 'path'")
           (handler-case
               (progn
                 (sb-ext:save-lisp-and-die path :executable t :purify nil)
                 (values (format nil "Saved image to ~A" path) nil))
             (error (e)
               (values nil (format nil "Save image error: ~A" e)))))))))

;;; --- Query Tool ------------------------------------------------------------

(defun make-query-tool ()
  (make-tool-spec
   "query"
   "Send a query to the LLM via the eval-loop."
   (plist-to-hash '("type" "object"
                    "properties" ("prompt" ("type" "string"))
                    "required" ("prompt")
                    "additionalProperties" nil))
   (lambda (args)
     (let ((prompt (cond
                     ((typep args 'hash-table) (gethash "prompt" args))
                     ((listp args) (cdr (assoc "prompt" args :test #'string=))))))
       (if (not (stringp prompt))
           (values nil "Error: Missing string argument 'prompt'")
           (let ((cfg (symbol-value (find-symbol "*CURRENT-CONFIG*" "HARNESS.STAGE-1.EVAL-LOOP"))))
             (if cfg
                 (let ((result (eval-loop prompt cfg)))
                   (values (result-content result) (result-error result)))
                 (values nil "Eval-loop not initialized"))))))))

;;; --- Refresh Model List Tool -----------------------------------------------

(defun make-refresh-model-list-tool ()
  (make-tool-spec
   "refresh-model-list"
   "Refresh the model list from NVIDIA API."
   (plist-to-hash '("type" "object"
                    "properties" ()
                    "additionalProperties" nil))
   (lambda (args)
     (declare (ignore args))
     (let ((provider (symbol-value (find-symbol "*PROVIDER*" "HARNESS.CORE"))))
       (if provider
           (handler-case
               (progn
                 (provider-refresh-models provider)
                 (values "Model list refreshed" nil))
             (error (e)
               (values nil (format nil "Refresh error: ~A" e))))
           (values nil "No provider available"))))))

;;;;;; --- Memory DB Tool (Semantic CRUD) ------------------------------------------

(defun make-memory-db-tool ()
  (make-tool-spec
   "memory-db"
   "Perform CRUD operations on the persistent semantic/chronological SQLite database.
    Actions:
    - insert: Save a fact or rule (processed=0 triggers background embedding).
    - find: Search for matching rules/facts by calculating cosine similarity against a query string.
    - update: Modify a record by ID (resets processed status to recalculate embedding).
    - delete: Remove a record by ID."
   (plist-to-hash '("type" "object"
                    "properties" ("action" ("type" "string" "enum" ("insert" "find" "update" "delete"))
                                  "id" ("type" "integer" "description" "Record ID (required for update/delete)")
                                  "session_id" ("type" "string" "default" "kb_facts" "description" "Namespace partition, e.g., kb_facts or kb_user_rules")
                                  "role" ("type" "string" "default" "system" "description" "Role tag, e.g., system, user, assistant")
                                  "content" ("type" "string" "description" "Content or query string (required for insert/find/update)")
                                  "limit" ("type" "integer" "default" 5 "description" "Maximum results to return for search"))
                    "required" ("action")
                    "additionalProperties" nil))
   (lambda (args)
     (let ((action (cond
                     ((typep args 'hash-table) (gethash "action" args))
                     ((listp args) (cdr (assoc "action" args :test #'string=)))))
           (id (cond
                 ((typep args 'hash-table) (gethash "id" args))
                 ((listp args) (cdr (assoc "id" args :test #'string=)))))
           (session-id (cond
                         ((typep args 'hash-table) (or (gethash "session_id" args) "kb_facts"))
                         ((listp args) (cdr (or (assoc "session_id" args :test #'string=)
                                                (cons "session_id" "kb_facts"))))))
           (role (cond
                   ((typep args 'hash-table) (or (gethash "role" args) "system"))
                   ((listp args) (cdr (or (assoc "role" args :test #'string=)
                                          (cons "role" "system"))))))
           (content (cond
                      ((typep args 'hash-table) (gethash "content" args))
                      ((listp args) (cdr (assoc "content" args :test #'string=)))))
           (limit (cond
                    ((typep args 'hash-table) (or (gethash "limit" args) 5))
                    ((listp args) (cdr (or (assoc "limit" args :test #'string=)
                                           (cons "limit" 5))))))
           (db (symbol-value (find-symbol "*DB*" "HARNESS.STAGE-0.DB"))))
       (unless db
         (setf db (uiop:symbol-call :harness.stage-0.db :init-db)))
       (cond
         ((string= action "insert")
          (if (not (stringp content))
              (values nil "Error: content is required for insert")
              (handler-case
                  (let ((new-id (uiop:symbol-call :harness.stage-0.db :insert-message
                                                  :session-id session-id
                                                  :role role
                                                  :content-raw content
                                                  :processed 0
                                                  :db db)))
                    (values (format nil "Successfully inserted message. ID: ~D" new-id) nil))
                (error (e) (values nil (format nil "Insert error: ~A" e))))))
         ((string= action "find")
          (if (not (stringp content))
              (values nil "Error: content (query string) is required for find")
              (handler-case
                  (let* ((query-vector (uiop:symbol-call :harness.stage-0.async-processor :get-embedding-via-nvidia content))
                         (hits (uiop:symbol-call :harness.stage-0.db :semantic-search-messages
                                                 query-vector
                                                 :session-id session-id
                                                 :limit limit
                                                 :db db)))
                    (if (null hits)
                        (values "No semantic matches found." nil)
                        (values (format nil "Semantic Search Matches:~%~{~A~%~}"
                                        (mapcar (lambda (h)
                                                  (format nil "ID: ~D | Similarity: ~,4F~%Content: ~A~%"
                                                          (getf h :id)
                                                          (getf h :similarity)
                                                          (getf h :content-raw)))
                                                hits))
                                nil)))
                (error (e) (values nil (format nil "Search error: ~A" e))))))
         ((string= action "update")
          (cond
            ((null id) (values nil "Error: id is required for update"))
            ((not (stringp content)) (values nil "Error: content is required for update"))
            (t (handler-case
                   (progn
                     (uiop:symbol-call :harness.stage-0.db :update-message
                                       id
                                       :session-id session-id
                                       :role role
                                       :content-raw content
                                       :processed 0
                                       :db db)
                     (values (format nil "Successfully updated message ~D." id) nil))
                 (error (e) (values nil (format nil "Update error: ~A" e)))))))
         ((string= action "delete")
          (if (null id)
              (values nil "Error: id is required for delete")
              (handler-case
                  (progn
                    (uiop:symbol-call :harness.stage-0.db :delete-message id :db db)
                    (values (format nil "Successfully deleted message ~D." id) nil))
                (error (e) (values nil (format nil "Delete error: ~A" e))))))
         (t (values nil (format nil "Unknown action: ~A" action))))))))

;;; --- Model Tool ------------------------------------------------------------

(defun make-model-tool ()
  (make-tool-spec
   "model"
   "Manage LLM model: list, select, or show current."
   (plist-to-hash '("type" "object"
                    "properties" ("action" ("type" "string" "enum" ("list" "select" "current"))
                                  "model" ("type" "string"))
                    "required" ("action")
                    "additionalProperties" nil))
   (lambda (args)
     (let ((action (cond
                     ((typep args 'hash-table) (gethash "action" args))
                     ((listp args) (cdr (assoc "action" args :test #'string=)))))
           (provider (symbol-value (find-symbol "*PROVIDER*" "HARNESS.CORE"))))
       (cond
         ((not (stringp action))
          (values nil "Error: Missing string argument 'action'"))
         ((string= action "list")
          (if provider
              (let ((models (provider-list-models provider)))
                (values (format nil "~{~A~%~}"
                                (mapcar (lambda (m)
                                          (format nil "  ~A (~A tokens)"
                                                  (getf m :id) (getf m :context-size)))
                                        models))
                        nil))
              (values nil "No provider available")))
         ((string= action "select")
          (let ((model (cond
                         ((typep args 'hash-table) (gethash "model" args))
                         ((listp args) (cdr (assoc "model" args :test #'string=))))))
            (if model
                (values "Model selection requires provider config update" nil)
                (values nil "Model name required"))))
         ((string= action "current")
          (if provider
              (let ((config (provider-config provider)))
                (values (format nil "Current model: ~A" (provider-config-default-model config)) nil))
              (values nil "No provider available")))
         (t (values nil (format nil "Unknown action: ~A" action))))))))

;;; --- Register All Standard Tools -------------------------------------------

(defvar *default-registry* (make-instance 'tool-registry))

(defvar *standard-tools-registered* nil)

(defun register-standard-tools (&optional (registry *default-registry*))
  "Register all standard tools into REGISTRY."
  (dolist (tool-fn '(make-bash-tool
                     make-read-file-tool
                     make-write-file-tool
                     make-edit-file-tool
                     make-save-image-tool
                     make-query-tool
                     make-refresh-model-list-tool
                     make-model-tool
                     make-memory-db-tool))
    (register-tool registry (funcall tool-fn)))
  (setf *standard-tools-registered* t)
  (format t "~&[harness.stage-4.tools] Registered ~A standard tools~%"
          (hash-table-count (registry-tools registry))))

(format t "~&[harness.stage-4.tools] Loaded~%")