(defpackage #:reflex.context
  (:use #:cl)
  (:export
   ;; Public API
   #:context-add
   #:context-caveman
   #:context-replay
   #:context-search
   #:context-assemble-prompt
   ;; Configuration
   #:*context-table-name*
   #:*caveman-version*
   #:*default-zone-budget*
   #:*embed-fn*
   #:*embed-dim*
   #:*persist-enabled*
   #:*current-session-id*
   ;; NVIDIA embedder
   #:*nvidia-embed-endpoint*
   #:*nvidia-embed-model*
   #:install-nvidia-embedder))
