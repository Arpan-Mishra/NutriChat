# NutriChat — CLAUDE.md

> **Read this file first, every session.**
> Then load the rule file that matches the codebase you are working in:
>
> | Codebase | Rule file |
> |----------|-----------|
> | `nutrichat-ios/` — SwiftUI iOS app | `.claude/rules/swift.md` |
> | `nutrichat-backend/` — FastAPI + PostgreSQL | `.claude/rules/backend.md` |
> | `nutrichat-python/` — PyPI SDK | `.claude/rules/python-sdk.md` |

---

## What This Project Is

NutriChat is a calorie-tracking iOS app whose main USP is WhatsApp bot integration.
Users link the app to a WhatsApp bot via a personal API key. Meals logged through
WhatsApp appear automatically in the iOS app, and vice versa.

Three permanently separate codebases. No shared code. No shared database.

```
nutrichat-ios/        SwiftUI iOS app   (JWT auth against backend)
nutrichat-backend/    FastAPI + PostgreSQL  ← build first, Sprints 1–6
nutrichat-python/     nutrichat PyPI SDK   (used by the WhatsApp CalorieBot)
```

### System architecture

```
┌─────────────────┐   HTTPS + JWT    ┌─────────────────────────────────┐
│  NutriChat iOS  │ ◄──────────────► │  NutriChat Backend (FastAPI)    │
│  (SwiftUI)      │                  │  /auth /food /diary             │
└─────────────────┘                  │  /goals /stats /apikeys         │
                                     └───────────────┬─────────────────┘
                                                     │ PostgreSQL (NutriChat's own)
                                                     │
                                     ┌───────────────┴─────────────────┐
                                     │   nutrichat PyPI package        │
                                     │   HTTPS + ApiKey header         │
                                     └───────────────┬─────────────────┘
                                                     │
                                     ┌───────────────┴─────────────────┐
                                     │  CalorieBot  (separate repo)    │
                                     │  FastAPI + LangGraph            │
                                     │  own DB (SQLite / PostgreSQL)   │
                                     └─────────────────────────────────┘
                                                     ▲
                                             WhatsApp Cloud API
```

**Data separation is absolute.** NutriChat has its own PostgreSQL.
CalorieBot has its own database. The only coupling between them is the
published PyPI package / NutriChat REST API.

---

## Git

**Remote:** `https://github.com/Arpan-Mishra/NutriChat`

### Step zero — run before AND after every task

```bash
git status
git diff --stat
```

### Auto-commit rule (MANDATORY)

After every task, calculate the change percentage:

```
changed_pct = (lines_added + lines_deleted) / total_lines_in_repo * 100
```

**If `changed_pct >= 10%` → commit and push immediately, without waiting.**

```bash
git add -A
git commit -m "<type>(<scope>): <description>"
git push origin main
```

### Commit message format (Conventional Commits)

```
<type>(<scope>): <short imperative description>

type  → feat | fix | refactor | test | docs | chore | style
scope → ios | backend | sdk | root
```

Examples:
```
feat(backend): add OTP request and verify endpoints
fix(ios): resolve keychain token deletion on logout
chore(sdk): publish v0.2.1 to PyPI
docs(root): update sprint plan for sprint 3
```

### Branch rules

- **Never force-push `main`**
- Use feature branches only for experimental or risky work:
  ```bash
  git checkout -b feat/whatsapp-linking
  # work...
  git push origin feat/whatsapp-linking
  # open PR → merge → delete branch
  ```

---

## Context7 MCP

Fetch live library documentation with Context7 **before** writing any implementation
that touches a framework API. Do not rely on training memory for method signatures —
they change between versions.

```
# Step 1 — resolve the library's Context7 ID
mcp__context7__resolve-library-id { libraryName: "fastapi" }

# Step 2 — fetch targeted docs
mcp__context7__get-library-docs {
  context7CompatibleLibraryId: "/tiangolo/fastapi",
  topic: "dependency injection"
}
```

Resolve these on first use in each domain:

| Domain | Libraries |
|--------|-----------|
| Backend | `fastapi`, `sqlalchemy`, `alembic`, `pydantic`, `httpx`, `python-jose`, `passlib`, `pytest` |
| SDK | `httpx`, `pydantic`, `pytest`, `respx` |
| iOS | `swiftui`, `swiftdata` |

---

## Universal Development Principles

These apply in every language and every codebase in this project.

| Principle | Rule |
|-----------|------|
| **Simplicity** | Write the simplest code that correctly solves the problem |
| **Readability** | Code is read 10× more than written — optimise for the reader |
| **Maintainability** | If future-you would struggle, simplify now |
| **Testability** | Every non-trivial unit must be testable in isolation |
| **Less Code = Less Debt** | Short files are a feature; delete freely; no speculative code |
| **Iterative build** | Minimal working slice first — verify it works, then add complexity |
| **Minimal changes** | Touch only code directly related to the current task |

### Coding practices (all languages)

- **Early returns** — flatten nested conditions; return or throw at the top
- **Descriptive names** — `handle_` (Python) / `handle` (Swift) prefix on all event handlers
- **Constants over magic values** — every literal has a named constant
- **DRY** — three identical lines → extract a function
- **Functional style** — prefer pure functions; push side-effects to the edges
- **Composing function first** — callers defined above callees in the same file
- **TODO comments** — `# TODO:` or `// TODO:` for known debt, never silent
- **Test frequently** — run tests after every meaningful change
- **Clean core logic** — I/O, formatting, error surfacing live at the boundary

---

## Environment Variables

- Never commit `.env` — always commit `.env.example` with placeholder values
- All secrets via environment variables — never hardcoded anywhere in source
- Variable names: `UPPER_SNAKE_CASE`
- Backend env vars fully documented in `.claude/rules/backend.md`