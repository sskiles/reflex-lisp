(in-package #:reflex.context)

(defparameter *nvidia-embed-endpoint*
  "https://integrate.api.nvidia.com/v1/embeddings"
  "NVIDIA integration API embeddings endpoint.")

(defparameter *nvidia-embed-model*
  "nvidia/nemotron-3-embed-1b"
  "Default NVIDIA embedding model.  nemotron-3-embed-1b produces 2048-dim vectors.")

(defun %ctx-nvidia-embed-request (text api-key model endpoint)
  "POST a single embedding request to NVIDIA.  Returns the response body as a string."
  (let* ((body (json:encode-json-alist-to-string
                (list (cons "input" text)
                      (cons "model" model))))
         (resp (dexador:post endpoint
                             :headers (list (cons "Content-Type" "application/json")
                                            (cons "Accept" "application/json"))
                             :bearer-auth api-key
                             :content body
                             :force-string t)))
    (cond
      ((stringp resp) resp)
      ((and (hash-table-p resp)
            (gethash "body" resp))
       (gethash "body" resp))
      (t (format nil "~S" resp)))))

(defun %ctx-parse-nvidia-embedding (body)
  "Extract the embedding vector from an NVIDIA embeddings response body."
  (let* ((json (json:decode-json-from-string body))
         (data (cdr (assoc :data json))))
    (unless data
      (error "No 'data' field in NVIDIA embeddings response: ~A" body))
    (let* ((first (car data))
           (vec (cdr (assoc :embedding first))))
      (unless vec
      (error "No 'embedding' field in NVIDIA embeddings response"))
      (coerce vec 'simple-vector))))

(defun %ctx-nvidia-embed (text &key
                                (api-key nil)
                                (model *nvidia-embed-model*)
                                (endpoint *nvidia-embed-endpoint*))
  "Embed TEXT using the NVIDIA integration API.
Returns a simple-vector of floats.  API-KEY defaults to the REFLEX
chat API key."
  (let* ((key (or api-key
                  (and (boundp '*default-api-key*)
                       (symbol-value '*default-api-key*))
                  (uiop:getenv "NVIDIA_API_KEY")))
         (body (%ctx-nvidia-embed-request text key model endpoint)))
    (%ctx-parse-nvidia-embedding body)))

(defun install-nvidia-embedder ()
  "Install the NVIDIA embedder as reflex.context:*embed-fn*.
Also sets *embed-dim* based on the model.  Call once after loading."
  (setf *embed-fn* #'%ctx-nvidia-embed)
  (setf *embed-dim*
        (case *nvidia-embed-model*
          ("nvidia/nemotron-3-embed-1b" 2048)
          ("nvidia/nv-embedqa-mistral-7b-v2" 4096)
          ("nvidia/embed-qa-4" 1024)
          (otherwise 2048)))
  (format t "~&[reflex.context] NVIDIA embedder installed: ~A (dim=~A)~%"
          *nvidia-embed-model* *embed-dim*))
