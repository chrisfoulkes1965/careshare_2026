# CareShare 2.0 — product backlog

**Sources:** *CareShare 2.0 Development Brief*, *UI Brief (April 2026)*, and `FIRESTORE_RULES_MATRIX.md` (derived from those briefs).  
Firestore data model and `firebase/firestore.rules` should stay aligned with the matrix for each epic.

**Legend:** *Remaining* = not fully delivered in the current app; many areas already have a **scaffold** (routes, rules, or partial UI) — this list is the full target scope.

---

## Current app (orientation only)

Roughly implemented today: authentication (incl. Google on mobile), user profile, setup wizard, **tasks**, **pathways**, **invitations**, **household notes**, **care group members** list, home shell.  
Everything below is either **partial** (needs completion to match the spec) or **not started** in the client.

---

## 1. Account, profile, and preferences

- **User profile** (`users/{uid}`): display name, photo / **avatar**, phone, date of birth as allowed by spec; self-update only; no client-writable `careGroupIds` unless you add a trusted path.
- **Simple Mode** (reduced density / larger type per UI brief): single source of truth on `users` and/or per **member** doc — product must pick one; settings UI to toggle.
- **Push readiness**: store **messaging FCM token** on the member (or user) document; self-only update per matrix.
- **First-run / returning user** flows: loading profile, resuming wizard, “needs household” empty states.
- **Account lifecycle**: prefer disable Auth + soft-delete over hard delete from the client (matrix).

---

## 2. Households, care group, and recipients

- **Household** create/update: name, description, `pathwayIds`, `recipientIds` / **recipient profiles**; **`principal_carer`** for settings updates; `careGroupId` not rewritable from untrusted client.
- **Edit household** UX: who sees what (carers read-only summary vs principal edits) per brief.
- **Care recipients:** managed profiles (no auth) vs **limited-app** access users; link `linkedRecipientProfileId` / `recipientId` on `users` for rules (`FIRESTORE_RULES_MATRIX` implementation checklist).
- **Care group**: name/identity; same creation story as setup wizard; optional soft-archive later.

---

## 3. Roles, membership, and invites (extend current)

- **Invitations** end-to-end: create (principal), list, cancel; invitee accept/decline with email match to verified auth.
- **Member management**: **assign roles** (`principal_carer`, `carer`, `receives_care`, `power_of_attorney`, `financial_manager`); display name/photo; remove member (principal); self-join paths if product adds them.
- **Kudos / leaderboard** (matrix): whether score is **client-writable** at all or **Cloud Function**-only; UI for “leaderboard” once rules allow.
- **Household / care group discovery** for invitees (already partly implied by rules).

---

## 4. Care pathways (extend current)

- **System pathways** (`system == true`): browse and attach to household `pathwayIds`.
- **Custom pathways** (`system == false`): create/update/delete by **principal** / owner per matrix; not editable like system content.
- Wizard **pathway selection** is partial — extend to full library + “my custom” story if in brief.

---

## 5. Tasks (extend current)

- Full **CRUD** and filters per household; **soft-delete / archive** and who can transition (open matrix item).
- **Assignee** / **recipient** semantics (align `assignedTo` / `recipientId` with real profile vs auth `uid` — see rules TODO on tasks).
- **Kudos**, **comments**, **voice note / voiceNoteUrl** on tasks with field allow-lists so privilege cannot be escalated via arbitrary fields.
- **Recipient (limited)**: which tasks are readable/visible — “relevant only” vs full list (TBD in matrix).

---

## 6. Notes (extend current)

- Categories and **sensitive / legal** notes: **POA** + **principal** read for restricted content; carers see general/medical as rules allow.
- **Delete** policy: carer only own vs principal any — align UI with locked rule choice.

---

## 7. Journal

- **Household journal** (`journalEntries`): timeline of entries; create/update by **principal** + **carer**; who sees what — **brief implies carers see feed**; **limited recipient** “own only vs all” **TBD** (matrix).

---

## 8. Calendar and scheduling

**Goal:** One place to plan care-related time — distinct from, but can **link to**, the **household meetings** subcollection in the matrix.

- **Care shifts** (who covers, when; handover notes optional later).
- **Medical** (GP, specialist, clinic).
- **Home / trades** (cleaner, maintenance, other trades).
- **Google Calendar integration** (one-way / two-way / per-user — product decision; ties to Google auth and OAuth scope choices).
- **Time zones**, recurring events, conflict hints (product TBD).
- **Meetings** (`households/.../meetings`): multi-party **care coordination meetings** (agenda, notes, follow-ups) — may surface as calendar events or a dedicated list; rules already assume principal+carer create; refine copy.

---

## 9. Medications

**Goal:** Safe med management per **caree**, aligned with `medications` subcollection rules.

- **List per caree** (name, form, strength, prescriber-facing notes as allowed).
- **Schedule** when doses are due (simple and complex schedules).
- **Reminders** (local + push) with **quiet hours**; FCM.
- **Stock / inventory** and **low-stock** warnings (units, packs, thresholds).
- **Batch preparation** (e.g. weekly) with a **checklist** to mark each med **processed** and optional audit trail.
- **Split “configuration” vs “taken / logged”** (matrix): carers logging “taken” should not rewrite dose/schedule — implement via **subdocuments**, **patch-only fields** in rules, or **Cloud Function**.

---

## 10. Expenses and household money

- **Expenses** (`expenses`): create by principal / **financial_manager**; read visibility for **carer** and **POA** per product sign-off (matrix default: not all carers see history unless you say so).
- **Update/delete** rules: who is payer; financial approver paths.
- Optional **receipts** in **Storage** with matching metadata (see Storage rules).

---

## 11. Documents and files

- **Household documents** with categories (e.g. **medical**, **other**, **legal**, **financial**); **sensitiveRoles**-style gating: legal/financial visibility for **principal**, **POA**, **financial_manager** as product defines.
- **Upload / list / open** flows; version or replace policy (TBD).
- Integrate with **Storage** security rules; virus scan / policy copy if required in your jurisdiction.

---

## 12. Contacts

- **Shared contact directory** for the household (CCGs, GPs, trades, family): CRUD for principal + carer; recipient visibility **conditional** (matrix).

---

## 13. Check-ins

- **Carer check-ins** and **recipient check-ins**; optional **private** carer check-ins: **not** readable by other carers from raw Firestore if `private == true` — use **aggregates** or **Cloud Functions** for principal summaries (matrix).
- Short **edit window** and self-only updates where the brief says so.

---

## 14. Chat (care group or household)

- **Group messaging** (recommended place in matrix: `careGroups/{careGroupId}/messages` or under household): at least **principal**, **carer**, **financial**, **POA**; **receives_care** rules are conservative in `firestore.rules` — product may expand.
- **Read-only / no edit** after send or edit window (matrix placeholder).

---

## 15. Notifications

- In-app and push **notification centre** (if stored: `users/{uid}/notifications` — **read/mark read = self**; **create = Cloud Function** on domain events).
- Map events: task assigned, invite, med reminder, expense approved, message, etc.

---

## 16. Location and safety (optional / gated)

- **Location, geofences, or device telemetry** only with explicit consent; **read** narrow (**principal** + **POA**; matrix); **ingest** via **Functions** or trusted path; no broad carer read of high-precision data unless brief explicitly allows.

---

## 17. Audit, compliance, and platform hardening

- **POA / sensitive action audit** (`households/{hid}/auditLogs/...` append-only, actor = self or Fn-only).
- **Field-level** validation in rules (allow-lists, `diff` checks) to block privilege escalation.
- **Indexes** for every query the app issues (see matrix note).
- **Custom claims** vs **member doc** reads: performance strategy (bundle, replication of `householdIds` on `users` via **Fn/Admin** only).
- **Web Google Sign-In** and **web OAuth** where not yet wired; **Google Calendar** OAuth scopes to be added when Calendar ships.

---

## 18. Cross-platform UX (UI Brief)

- Consistent use of **theme** (`AppColors`, typography, spacing) and **accessibility** (contrast, touch targets, Simple Mode).
- **Desktop / tablet / web** layouts where the brief requires responsive behaviour.

---

## Open questions (from matrix — block before locking rules in production)

1. **Expenses:** can all **carers** see expense history, or only **financial_manager** + **principal**?  only financial manager
2. **Limited recipient users:** which collections are readable (chat, documents, meetings, full tasks vs **assigned** only)?  
3. **Simple Mode:** one storage location — `users` only, `members` only, or both?  
4. **Tasks:** soft-delete vs `archived` — who can transition?  
5. **Kudos score:** any client write, or **Function-only**?  
6. **Journal / meetings / calendar:** single mental model for users (merge vs separate surfaces)?

---

*Calendar and Medications in §8–9 include backlog items you prioritised; all other sections reflect the **Development Brief** as captured in the rules matrix. External brief PDFs are not in this repo; update this file if the source brief changes.*
