(in-package #:reflex.context)

(defvar *persist-enabled* t
  "When non-nil, agent turns are persisted to the context table.
Set to NIL to disable without removing the calls.")

(defvar *current-session-id* "default"
  "Session id used by %PERSIST-TURN.  The query loop updates this.")

(defun %next-seq (session-id)
  "Return the next seq number for SESSION-ID (max(seq)+1, or 1)."
  (let* ((db (%ctx-connect))
         (stmt (sqlite:prepare-statement
                db
                (format nil
                        "SELECT COALESCE(MAX(seq), 0) + 1
                         FROM ~A WHERE session_id = ?"
                        *context-table-name*)))
         (next 1))
    (unwind-protect
         (progn
           (sqlite:bind-parameter stmt 1 session-id)
           (when (sqlite:step-statement stmt)
             (setf next (sqlite:statement-column-value stmt 0))))
      (sqlite:finalize-statement stmt))
    (sqlite:disconnect db)
    next))

(defun %persist-turn (kind role content &key tool-name tool-call-id session-id)
  "Persist a single turn to the context table.
Returns the new row id, or NIL if persistence is disabled or fails."
  (unless *persist-enabled*
    (return-from %persist-turn nil))
  (let ((sid (or session-id *current-session-id*)))
    (handler-case
        (context-add :session-id sid
                     :seq (%next-seq sid)
                     :kind kind
                     :role role
                     :content content
                     :tool-name tool-name
                     :tool-call-id tool-call-id)
      (error (e)
        (format *error-output*
                "~&[reflex.context] persist failed: ~A~%" e)
        nil))))
