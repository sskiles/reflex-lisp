# AGENTS.md – Kick‑starting Future Agents with Reflex

## Purpose

This document is a **conceptual starter kit** for building, experimenting with, and evolving *future AI agents* inside the **Reflex** harness.  
It is aimed at **developers and researchers** who want to:

- **Bootstrap** new agent behaviours on‑the‑fly.  
- **Iterate** rapidly by editing, persisting, and rolling back changes without stopping the runtime.  
- **Leverage** the self‑referential nature of Reflex so that the agent can reason about—and even modify—its own architecture.

> **Bottom line:** Reflex provides a *living laboratory* where an agent’s code, memory, and toolset are mutable, observable, and versioned in real time.

---

## Core Concepts

| Concept | What it Means for an Agent |
|--------|----------------------------|
| **Self‑reference** | The agent can inspect and rewrite its own source, its memory store, and the tool registry it uses. |
| **Dynamic Toolbox** | Tools (e.g., `bash`, `http-request`, `list-directory`) are first‑class objects that the agent can add, remove, or replace while it runs. |
| **In‑memory Definitions** | All behaviour starts as symbols in the Lisp image; nothing is “locked” until the agent chooses to persist it. |
| **Backup & Rollback** | Every `persist` creates a timestamped backup, giving the agent a safe way to revert or audit changes. |
| **Continuous Experimentation** | Because the image never stops, the agent can test, observe, and refine indefinitely. |

---

## How to Kick‑Start an Agent

1. **Define a Goal** – Articulate the desired capability (e.g., *“summarize a directory listing”*).  
2. **Generate a Tool** – Let the LLM produce the corresponding Lisp form (a function, macro, or API wrapper).  
3. **Persist the Tool** – Call `harness.live-patch:persist` on a fresh file in `tools/` (e.g., `tools/dir-summary.lisp`).  
   - The current in‑memory definition is written to disk, and a backup of the previous file is saved automatically.  
4. **Expose the Tool** – Add an entry to the **tool‑registry** (or use an existing one) so the agent can invoke it via a simple name, such as `:list-dir-summary`.  
5. **Iterate** – Use the newly available tool in subsequent prompts, observe output, and immediately edit the source if needed.  
   - Any edits are persisted again, creating another backup, allowing endless cycles of *modify → test → persist* without a restart.

---

## Agent Lifecycle Inside Reflex

1. **Creation** – The agent is spawned as a set of symbols and an initial configuration stored in memory.  
2. **Exploration** – It can query the **memory‑store**, inspect the **tool‑registry**, and call any loaded **live‑patch** functions.  
3. **Modification** – By editing its own source files on disk, the agent reshapes its behaviour in real time.  
4. **Persistence** – When a change is required to survive restarts, `persist` writes the new code to disk and timestamps a backup.  
5. **Rollback** – If a modification proves harmful, the agent can load the most recent backup, or any earlier backup, and resume from a known good state.  
6. **Evaluation** – The agent can introspect its own source (e.g., via `diff`) to compare intended vs. actual behaviour, supporting meta‑reasoning and self‑critique.

---

## Minimal Skeleton for a New Agent

```lisp
;; tools/new-agent.lisp   ← first draft, loaded into memory
(defun new-agent (goal)
  "Create a simple agent that works toward a single goal."
  (if (null goal)
      (error "Goal required")
      (let ((plan (make-plan goal)))   ; pseudo‑function
        (plan)))                       ; execute plan

;; later, from the REPL or LLM prompt:
(harness.live-patch:persist "tools/new-agent.lisp")
```

- The above file is **ephemeral**; until it is persisted, the function lives only in memory.  
- After `persist`, the agent can call `(new-agent "explore-dir")` at any time, and any subsequent edit to `new-agent.lisp` can be persisted again, creating a fresh backup each time.

---

## Best‑Practice Checklist for Researchers

- **Keep backups**: after each `persist`, verify a backup exists; consider labeling important milestones.  
- **Version concepts**: treat a series of backups as a lightweight version control system for the agent’s code.  
- **Isolate experiments**: use separate files under `tools/` for distinct capabilities, making it easier to roll back individual components.  
- **Leverage meta‑commands**: commands like `diff` let the agent compare the on‑disk version with the live version, supporting self‑diagnostics.  
- **Document pathways**: add short comment blocks at the top of each tool file describing its purpose and expected inputs/outputs – this aids both human and agent reasoning.  

---

## Future Directions (Conceptual)

- **Multi‑agent composition** – combine several independently persisted tools into a coordinated workflow.  
- **Self‑evaluation loops** – let an agent generate critique prompts that ask itself to assess recent changes, then persist improvements.  
- **Resource‑aware scheduling** – query and adjust the **memory‑store** or **compute budget** dynamically, enabling agents that reason about their own cost/benefit trade‑offs.  

These ideas are *speculative* but align with the core Reflex principle: **the environment is as malleable as the agent itself**.

---

### Quick Reference for Developers

| Command | Effect |
|--------|--------|
| `harness.live-patch:persist "<path>.lisp"` | Writes current in‑memory definitions to `<path>.lisp`, creates a timestamped backup, and makes the file instantly usable. |
| `harness.live-patch:diff "<path>.lisp"` | Shows a side‑by‑side comparison of on‑disk vs. in‑memory versions, helping verify that the latest changes are loaded. |
| `harness.memory:store-get` / `store-set` | Query or modify the shared memory‑store used for persisting temporary state. |
| `harness.tool-registry:define name lambda-list` | Register a new tool name that the agent can invoke directly. |
| `harness.live-patch:rollback` | Restores the most recent backup of the currently edited file, enabling safe rollback. |

---  

*Prepared for developers and researchers interested in kicking‑started, self‑referential AI agents within the Reflex ecosystem.*

---  

*The file is written to `/home/reflex/lisp/arch3/AGENTS.md`.*