;;;; async-processor.lisp - Background Worker for Embedding and Caveman processing

(defpackage #:harness.stage-0.async-processor
  (:use #:cl)
  (:export
   #:start-background-processor
   #:stop-background-processor
   #:process-caveman-string
   #:get-embedding-via-nvidia
   #:*processing-interval*))

(in-package #:harness.stage-0.async-processor)

(defvar *processor-thread* nil
  "The thread handling the background processing.")

(defvar *processor-active* nil
  "Flag indicating if the background processor is active.")

(defvar *processing-interval* 2.0
  "Interval in seconds to check for new unprocessed rows in the database.")

;;; --- local caveman summarizer (Regular Expressions) ---

(defparameter *caveman-stop-words*
  '("the" "a" "an" "and" "or" "but" "is" "are" "was" "were" "be" "been" "being" 
    "to" "of" "in" "on" "at" "by" "for" "with" "about" "against" "between" "into" 
    "through" "during" "before" "after" "above" "below" "from" "up" "down" "in" 
    "out" "on" "off" "over" "under" "again" "further" "then" "once" "here" "there" 
    "when" "where" "why" "how" "all" "any" "both" "each" "few" "more" "most" "other" 
    "some" "such" "no" "nor" "not" "only" "own" "same" "so" "than" "too" "very" 
    "s" "t" "can" "will" "just" "don" "should" "now" "i" "me" "my" "myself" "we" 
    "our" "ours" "ourselves" "you" "your" "yours" "yourself" "yourselves" "he" 
    "him" "his" "himself" "she" "her" "hers" "herself" "it" "its" "itself" "they" 
    "them" "their" "theirs" "themselves" "what" "which" "who" "whom" "this" "that" 
    "these" "those" "am" "has" "have" "had" "having" "do" "does" "did" "doing" 
    "would" "should" "could" "ought" "i'm" "you're" "he's" "she's" "it's" "we're" 
    "they're" "i've" "you've" "we've" "they've" "i'd" "you'd" "he'd" "she'd" "we'd" 
    "they'd" "i'll" "you'll" "he'll" "she'll" "we'll" "they'll" "isn't" "aren't" 
    "wasn't" "weren't" "hasn't" "haven't" "hadn't" "doesn't" "don't" "didn't" 
    "won't" "wouldn't" "shan't" "shouldn't" "can't" "cannot" "couldn't" "mustn't" 
    "let's" "that's" "who's" "what's" "here's" "there's" "when's" "where's" "why's" 
    "how's" "a's" "b's" "c's" "d's" "e's" "f's" "g's" "h's" "i's" "j's" "k's" "l's" 
    "m's" "n's" "o's" "p's" "q's" "r's" "s's" "t's" "u's" "v's" "w's" "x's" "y's" 
    "z's" "us")
  "List of English stop words to strip for caveman representation.")

(defun process-caveman-string (text)
  "Convert the raw text into a caveman representation:
   1. Downcase the entire string.
   2. Remove punctuation.
   3. Strip stop words.
   4. Normalize spacing."
  (if (or (null text) (string= text ""))
      ""
      (let* ((downcased (string-downcase text))
             ;; Replace non-alphanumeric/non-space chars with spaces
             (no-punc (cl-ppcre:regex-replace-all "[^a-z0-9\\s]" downcased " "))
             (words (cl-ppcre:split "\\s+" no-punc))
             (filtered-words (remove-if (lambda (w)
                                          (or (string= w "")
                                              (member w *caveman-stop-words* :test #'string=)))
                                        words)))
        (format nil "~{~A~^ ~}" filtered-words))))

;;; --- NVIDIA Embedding Retrieval ---

(defun get-embedding-via-nvidia (text)
  "Retrieve embedding array for TEXT from NVIDIA API using nvidia/nv-embed-v1."
  (let ((api-key harness.stage-0.nvidia:*nvidia-api-key*))
    (unless api-key
      (error "NVIDIA_API_KEY environment variable is not set"))
    (let* ((url "https://integrate.api.nvidia.com/v1/embeddings")
           (payload (harness.stage-0.nvidia::ht
                     "input" (list text)
                     "model" "nvidia/nv-embed-v1"
                     "encoding_format" "float"
                     "input_type" "query")) ; or "passage" depending on query vs document. Standard query is versatile
           (resp (dexador:post url
                               :content (json:encode-json-to-string payload)
                               :headers `(("Authorization" . ,(format nil "Bearer ~A" api-key))
                                          ("Content-Type" . "application/json"))
                               :connect-timeout harness.stage-0.nvidia::*request-timeout*
                               :read-timeout harness.stage-0.nvidia::*request-timeout*))
           (parsed (json:decode-json-from-string resp))
           (data (harness.stage-0.nvidia::json-get parsed "data"))
           (first-item (first data))
           (embedding-list (harness.stage-0.nvidia::json-get first-item "embedding")))
      (coerce embedding-list 'vector))))

;;; --- Worker Loop & Thread Lifecycle ---

(defun process-next-pending-message (db)
  "Look for one message with processed = 0, process it, and save it."
  (let ((row (first (sqlite:execute-to-list
                     db
                     "SELECT id, content_raw FROM messages WHERE processed = 0 LIMIT 1;"))))
    (when row
      (destructuring-bind (id content-raw) row
        (handler-case
            (let* ((caveman (process-caveman-string content-raw))
                   (embedding (get-embedding-via-nvidia content-raw)))
              (harness.stage-0.db:update-message
               id
               :content-caveman caveman
               :embedding embedding
               :processed 1
               :db db)
              t)
          (error (e)
            (format *error-output* "~&[Async Processor] Error processing row ~D: ~A~%" id e)
            ;; Sleep briefly to avoid infinite rapid retries on transient errors
            (sleep 2)
            nil))))))

(defun worker-loop (db-path)
  (format t "~&[Async Processor] Worker thread started.~%")
  (sqlite:with-open-database (db db-path)
    (sqlite:execute-non-query db "PRAGMA busy_timeout = 5000;")
    (loop while *processor-active*
          do (handler-case
                 (unless (process-next-pending-message db)
                   ;; If no rows were processed, sleep before checking again
                   (sleep *processing-interval*))
               (error (e)
                 (format *error-output* "~&[Async Processor] Loop error: ~A~%" e)
                 (sleep *processing-interval*)))))
  (format t "~&[Async Processor] Worker thread exiting.~%"))

(defun start-background-processor (db-path)
  "Launch the background worker thread if not already running."
  (if *processor-thread*
      (format t "~&[Async Processor] Already running.~%")
      (progn
        (setf *processor-active* t)
        (setf *processor-thread*
              (bt:make-thread (lambda () (worker-loop db-path))
                              :name "context-engine-background-processor"))
        (format t "~&[Async Processor] Started background thread.~%"))))

(defun stop-background-processor ()
  "Signal the background worker to terminate and wait for it to join."
  (when *processor-thread*
    (setf *processor-active* nil)
    (bt:join-thread *processor-thread*)
    (setf *processor-thread* nil)
    (format t "~&[Async Processor] Stopped background thread.~%")))
