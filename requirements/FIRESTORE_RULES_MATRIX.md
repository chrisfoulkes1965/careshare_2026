# CareShare 2.0 — Firestore security rules matrix

This document maps **roles** and **collections** from the Development Brief to recommended **allow/deny/conditional** behaviour for `firestore.rules`. It is a specification aid, not a drop-in rules file.

## Definitions

### Who counts as a “household member”?

A user `uid` may read/write household-scoped data if they are a member of the **care group linked to that household** (the brief uses `households.careGroupId` and `careGroups.householdId`). Rules should resolve membership via **`careGroups/{careGroupId}/members/{uid}`** (or equivalent denormalised claim) rather than trusting client-supplied `householdId` alone.

### Roles (per `careGroups/{id}/members/{uid}.roles[]`)

| Role ID (suggested) | Brief name |
|---------------------|------------|
| `carer` | Carer |
| `principal_carer` | Principal Carer |
| `receives_care` | Receives Care |
| `power_of_attorney` | Power of Attorney |
| `financial_manager` | Financial Manager |

**Principal Carer** is treated as **including Carer** unless you explicitly split permissions in product copy.

### Care recipient access modes

| Mode | Auth user? | Rules stance |
|------|------------|----------------|
| Managed profile | No Firebase user for recipient | Carers act on recipient data; recipient has no direct rules |
| Limited access | Yes (`uid`) | Read-focused; writes only where the brief explicitly allows (e.g. own check-in, consent flows). **Recipient must not edit tasks/notes created by carers.** |

The brief leaves some edges unspecified; cells marked **TBD** need product sign-off before coding.

---

## Global collections

### `users/{userId}`

| Operation | Condition / notes |
|-----------|-------------------|
| **read** | Self (`request.auth.uid == userId`), or household peers (optional denormalisation for profiles — else load via Cloud Function / limited fields only). |
| **create** | On first sign-up (`userId == request.auth.uid`) with schema validation. |
| **update** | Self only; validate mutable fields (`displayName`, `photoUrl`, `avatarIndex`, `phone`, `dateOfBirth`, `simpleMode`, …). Do not allow client to set `careGroupIds` unless you implement server-side membership writes. |
| **delete** | Prefer **disable Auth** + soft-delete flag; avoid hard delete from client. |

### `invitations/{invitationId}`

| Operation | Condition / notes |
|-----------|-------------------|
| **read** | Invitee: `resource.data.invitedEmail` normalised equals caller’s verified email; OR inviter / principal on linked `careGroupId`; OR existing member of that care group (for “pending invites” UI). |
| **create** | Caller is member of `careGroupId` with **`principal_carer`** (brief: invite flow). |
| **update** | Invitee accepting/declining (match email → auth); optionally principal cancels (status → `declined` / delete). |
| **delete** | Principal or system cleanup only. |

### `carePathways/{pathwayId}`

| Operation | Condition / notes |
|-----------|-------------------|
| **read** | Authenticated: **`system == true`** pathways for all; **`system == false`**: only creators / households that reference `pathwayId` (needs `pathwayIds` on household or shared allowlist). |
| **create** | **`principal_carer`** on some household that will own the custom pathway, or admin-only if you centralise custom pathways. |
| **update / delete** | **`system == true`**: deny client writes; **`system == false`**: creator / principal_carer for linked household only. |

### `careGroups/{careGroupId}`

| Operation | Condition / notes |
|-----------|-------------------|
| **read** | Member of `careGroups/{careGroupId}/members/{uid}`. |
| **create** | Authenticated user creating household+wizard flow (often same as household create). |
| **update** | **`principal_carer`** on that group (name tweaks, etc.). Tighten if fields are immutable after create. |
| **delete** | Admin / principal only; prefer soft-archive. |

### `careGroups/{careGroupId}/members/{userId}`

| Operation | Condition / notes |
|-----------|-------------------|
| **read** | Any member of the same `careGroupId` (brief: view profiles, leaderboard). |
| **create** | Self-join via invite acceptance, or **`principal_carer`** adding member, or Cloud Function on invite. |
| **update** | **Roles / displayName / photoUrl**: **`principal_carer`** only (brief: assign roles). **`kudosScore`**: restrict to privileged writes (increment via **Cloud Function** or security rule with `request.resource.data.diff(resource.data).affectedKeys()` only allowing `kudosScore`). **`simpleMode`**: if stored per-member, **self** only; if duplicated from `users`, pick one source of truth. **`messagingToken`**: **self** only. |
| **delete** | **`principal_carer`** (remove member). |

---

## Household root: `households/{householdId}`

Assume helper `isHouseholdMember(householdId, uid)` → member doc exists on `household.careGroupId`.

| Field / op | principal_carer | carer | financial_manager | power_of_attorney | receives_care (limited) |
|------------|-----------------|-------|---------------------|-------------------|-------------------------|
| **read** | Yes | Yes | Yes | Yes | Yes, if limited recipient is tied to this household (TBD: prove linkage via `recipientIds` containing a profile id vs `uid`). |
| **create** | Yes (wizard) | Deny (unless you allow co-creation) | Deny | Deny | Deny |
| **update** (`name`, `description`, `pathwayIds`, `recipientIds`) | Yes | Deny or **read-only** (brief: “Edit Household” — assign to principal only unless clarified) | Deny | Deny | Deny |
| **update** (`careGroupId`) | Deny from client (server-only link) | Deny | Deny | Deny | Deny |

**Recommendation:** treat household **settings** updates as **`principal_carer`** only; carers consume read-only household summary.

---

## Household subcollections

Legend: **Y** = allow, **N** = deny, **C** = conditional (see notes), **Fn** = prefer **Cloud Function** / trusted worker for writes.

### `households/{hid}/tasks/{taskId}`

| Op | principal | carer | financial | poa | recipient (limited) |
|----|-----------|-------|-------------|-----|------------------------|
| read | Y | Y | Y | Y | **C**: tasks linked to recipient **or** assigned to recipient user id (TBD: “relevant tasks”). |
| create | Y | Y | N | N | N |
| update | Y | Y | N | N | **C**: status transitions only if assignee is self? Brief says cannot edit — default **N**. |
| delete (soft) | Y | **C**: own-created only vs principal deletes any — brief ambiguous; safest **principal only** for `status == deleted` | N | N | N |

**Kudos / comments / voiceNoteUrl:** validate field allow-lists on update so carers cannot escalate privilege via arbitrary field writes.

### `households/{hid}/notes/{noteId}`

| Op | principal | carer | financial | poa | recipient |
|----|-----------|-------|-------------|-----|-------------|
| read | Y | Y | Y | **C**: sensitive notes — if you add `sensitive: true` or category `legal`, restrict to **poa** + **principal** (brief: POA sensitive notes). |
| create | Y | Y | N | Y | N |
| update | Y | Y | N | Y | N |
| delete / archive | Y | **C** | N | Y | N |

### `households/{hid}/journalEntries/{entryId}`

| Op | principal | carer | financial | poa | recipient |
|----|-----------|-------|-------------|-----|-------------|
| read | Y | Y | Y | Y | **C**: own entries vs all — brief implies carers see feed; recipient visibility **TBD**. |
| create | Y | Y | N | N | N |
| update | Y | Y (own?) | N | N | N |

### `households/{hid}/medications/{medicationId}`

| Op | principal | carer | financial | poa | recipient |
|----|-----------|-------|-------------|-----|-------------|
| read | Y | Y | N | Y | **C**: own recipient’s meds only if limited app |
| create / update | Y | **C**: carers log “taken” — use **Fn** or allow patch only on `lastTaken`-style fields | N | Y | N |

Brief: medication **configuration** vs **mark taken** — splitting subdocuments or using Cloud Functions avoids carers editing dose/schedule.

### `households/{hid}/expenses/{expenseId}`

| Op | principal | carer | financial | poa | recipient |
|----|-----------|-------|-------------|-----|-------------|
| read | Y | **C** (brief: expense visibility not explicit; default **N** for plain carer unless “view history” is all members) | Y | **C** | N |
| create | Y | N | Y | N | N |
| update | Y | N | **C**: payer or financial_manager | N | N |
| delete | Y | N | **C** | N | N |

**Clarify with product:** are expenses visible to all carers or only **financial_manager** + **principal**?

### `households/{hid}/meetings/{meetingId}`

| Op | principal | carer | financial | poa | recipient |
|----|-----------|-------|-------------|-----|-------------|
| read | Y | Y | Y | Y | N (unless you open meetings to recipient) |
| create / update | Y | Y | N | N | N |

### `households/{hid}/documents/{documentId}`

| Op | principal | carer | financial | poa | recipient |
|----|-----------|-------|-------------|-----|-------------|
| read | Y | **C**: category `medical`/`other` yes; **`legal`/`financial`**: **principal** + **poa** (+ **financial** for `financial`?) | **C** | Y | N |
| create | Y | **C**: non-sensitive categories only, or all with post-upload scan — simplest: **principal** + **poa** for legal uploads | **C** | Y | N |
| update / delete | Y | N | N | Y | N |

Map **`sensitiveRoles`** on the document to dynamic checks: caller must have intersection of `resource.data.sensitiveRoles` and their `roles[]`.

### `households/{hid}/contacts/{contactId}`

| Op | principal | carer | financial | poa | recipient |
|----|-----------|-------|-------------|-----|-------------|
| read | Y | Y | Y | Y | **C** |
| create / update / delete | Y | Y | N | N | N |

### `households/{hid}/checkins/{checkinId}`

| Op | principal | carer | financial | poa | recipient |
|----|-----------|-------|-------------|-----|-------------|
| read | Y | **C**: `private == true` → **self only**; aggregate for principal (brief) via **Fn** or allow read of anonymised summary docs only | N | N | **C**: recipient-type visible to group; carer-type private |
| create | Y | Y (own carer check-in) | N | N | Y (own recipient check-in) |
| update | **C** | **C** self only, short window | N | N | **C** self only |

**Private carer check-ins** should not be readable by other carers from raw Firestore if the brief says private; use aggregated docs or **Fn**.

---

## Chat (not fully specified in Firestore brief)

If implemented as **`careGroups/{careGroupId}/messages/{messageId}`** (recommended) or under `households/{hid}/messages`:

| Op | principal | carer | financial | poa | recipient |
|----|-----------|-------|-------------|-----|-------------|
| read | Y | Y | Y | Y | **C** (if recipients join chat — brief focuses on carers; default **N**) |
| create | Y | Y | Y | Y | **C** |
| update / delete | **C** (edit window / admin) | **C** own | … | … | … |

---

## Notifications (if stored in Firestore)

Typical pattern: `users/{uid}/notifications/{id}` **read/update (mark read)** = **self only**; **create** = **Cloud Function** on events.

---

## Tracking / location (if stored)

| Data | Suggested rule |
|------|----------------|
| Live location, geofences, device telemetry | **Write**: tracked device owner / consent flow only, or **ingest via Fn**; **Read**: **principal_carer** + **poa** only; **audit log** append-only via **Fn**. |

Do not store high-precision location readable by all carers unless the brief explicitly expands visibility.

---

## Implementation checklist

1. **Custom claims vs member doc reads**: Rules that `get()` `careGroups/.../members/{uid}` on every query can get expensive; consider [Firestore bundle rules patterns](https://firebase.google.com/docs/firestore/security/rules-conditions#access_other_documents) or replicated `householdIds[]` on `users` maintained only by **Fn/Admin**.
2. **Field-level validation**: Use `request.resource.data.keys().hasOnly([...])` / diff checks so a carer cannot grant themselves `principal_carer` via a poisoned write path.
3. **Recipient limited user**: Add explicit **`linkedRecipientProfileId`** or `householdId` + `recipientId` on `users` for rules to evaluate **C** rows without ambiguity.
4. **POA audit trail**: Implement as **`households/{hid}/auditLogs/{id}`** append-only (create via Fn or allow create if `request.resource.data.actorId == request.auth.uid` and deny updates).
5. **Indexes**: Matrix does not replace required composite indexes for queries filtered by `householdId`, `assignedTo`, `status`, etc.

---

## Open questions for product (resolve before locking rules)

1. Can **carers** see **all** expenses or only **financial_manager** + **principal**?
2. For **limited recipient** users: exactly which collections are readable (chat, documents, meetings, full task list vs assigned-only)?
3. Is **Simple Mode** stored on **`users`** only, **`members`** only, or both (rules should read one)?
4. **Soft-deleted tasks**: new `status == 'archived'` vs delete — who can transition?
5. **Kudos score**: client-writable at all, or **Fn-only**?

---

*Derived from CareShare 2.0 Development Brief and UI Brief (April 2026).*
