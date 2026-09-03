(in-package #:reflex.context)

(defun %ctx-insert-row (db kind content role session-id turn-id seq tags
                                 embedding embed-model tool-name tool-call-id)
  "Execute the INSERT statement and return the new row id."
  (let* ((ts (get-universal-time))
         (hash (%ctx-sha256 content))
         (tokens (%ctx-estimate-tokens content))
         (packed (when embedding
                   (%ctx-pack-f32-embedding
                    (if (vectorp embedding)
                        embedding
                        (coerce embedding 'simple-vector)))))
         (dim (when embedding (length embedding)))
         (norm (when embedding
                 (%ctx-l2-norm
                  (if (listp embedding)
                      embedding
                      (coerce embedding 'list)))))
         (caveman (%ctx-caveman-from-row kind content))
         (caveman-tokens (%ctx-estimate-tokens caveman)))
    (sqlite:execute-non-query
     db
     (format nil
             "INSERT INTO ~A
  (ts, kind, role, content, content_hash, token_count,
   session_id, turn_id, seq, tags,
   embedding, embed_model, embed_dim, embed_dtype, embed_norm,
   caveman, caveman_tokens, caveman_v,
   tool_name, tool_call_id)
VALUES
  (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
             *context-table-name*)
     ts kind (or role kind) content hash tokens
     session-id turn-id seq tags
     packed embed-model dim "f32" norm
     caveman caveman-tokens *caveman-version*
     tool-name tool-call-id)
    (sqlite:last-insert-rowid db)))

(defun context-add (&key kind content role session-id turn-id seq tags
                             embedding embed-model
                             tool-name tool-call-id)
  "Insert a single row into the context table.  Returns the new row id."
  (let ((db (%ctx-connect)))
    (unwind-protect
         (%ctx-insert-row db kind content role session-id turn-id seq tags
                                   embedding embed-model tool-name tool-call-id)
      (sqlite:disconnect db))))
