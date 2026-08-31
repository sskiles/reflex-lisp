# Reflex

Reflex is a fresh Common Lisp foundation for a self‑referential LLM agent
harness.  The first functional milestone is deliberately small: an HTTP module
that sends a prompt to an OpenAI-compatible chat-completions endpoint and
returns the response text.

## Layout

```text
reflex.asd              ASDF system definition
start-harness.sh        Interactive SBCL/RLWRAP entry point
src/package.lisp        Public package and exports
src/api.lisp            Minimal endpoint client
src/reflex.lisp         Main system file, currently a placeholder
test/test-api.lisp      Network-free smoke tests with a fake transport
REFLEX.md               Conceptual project brief
```

## Load the system

```bash
./start-harness.sh
```

Or from a Lisp image with Quicklisp initialized:

```lisp
(ql:quickload '(#"dexador" #"cl-json") :silent t)
(asdf:load-asd #p"/home/reflex/common-lisp/reflex/reflex.asd")
(asdf:load-system :reflex)
```

## Send a prompt

```lisp
(setf reflex:*default-api-key* "sk-...")
(reflex:ask "Say hello from Reflex.")
```

Keywords accepted by `reflex:send-prompt` and therefore by `reflex:ask`:

- `:url` — default is `reflex:*default-endpoint*`
- `:api-key` — default is `reflex:*default-api-key*`
- `:model` — default is `reflex:*default-model*`
- `:temperature`
- `:max-tokens`
- `:top-p`
- `:stop`
- `:request-function` — inject a test or alternate transport

The client currently expects the OpenAI chat-completions request/response
shape:

```json
{
  "model": "...",
  "messages": [
    {"role": "user", "content": "..."}
  ]
}
```

and extracts `choices[0].message.content` from successful responses.

## Run smoke tests

```lisp
(asdf:test-system :reflex)
```

The tests use a fake transport and perform no network calls.
