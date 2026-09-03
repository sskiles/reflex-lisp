(in-package #:reflex.context)

(defvar *embed-fn* nil
  "Function (lambda (text) vector-of-floats) used to embed queries.
Set this to plug in your embedding model (e.g. a local sentence-transformers
call or a remote API).  When NIL, context-assemble-prompt will signal an
error if it needs to embed a query.")

(defvar *embed-dim* nil
  "Dimension of the embedding model.  When set, context-add can validate
that user-supplied embeddings match.")

(defun %ctx-embed (text)
  "Embed TEXT using *EMBED-FN*.  Signals an error if no embedder is configured."
  (unless *embed-fn*
    (error "No embedding function configured.  Set reflex.context:*embed-fn*."))
  (funcall *embed-fn* text))
