# auth.users display_name — Edge Functions and Flutter

## Status

- **create_user_admin**: Sets `auth.users.display_name` and `raw_user_meta_data.name` at creation. Flutter sends `display_name` in body (format: `"Surname, Forename"`).
- **update_user_admin**: Deployed. When `display_name` is sent, it sets `auth.users.display_name` and mirrors to `user_metadata.name`. Flutter sends `display_name` on user edit (same format).

## update_user_admin (deployed)

**Endpoint:** `POST https://<project>.supabase.co/functions/v1/update_user_admin`  
**Auth:** `Authorization: Bearer <admin/service JWT>` (verify_jwt enabled).

**Request body:**

| Field         | Type   | Required | Description |
|---------------|--------|----------|-------------|
| `user_id`     | string | Yes      | Auth user UUID. |
| `display_name`| string \| null | No | If non-empty: sets auth.users.display_name and user_metadata.name. If null: clears display_name. |
| `user_metadata` | object \| null | No | Merged with metadata (name is set from display_name when display_name is provided). |
| `app_metadata`  | object \| null | No | Replaces app_metadata. |

**Behavior:**

- Non-empty `display_name`: sets `auth.users.display_name` and ensures `user_metadata.name` matches.
- `display_name: null`: clears `auth.users.display_name`; `user_metadata` unchanged unless you pass `user_metadata`.
- Pass `user_metadata` alone (no `display_name`) to update only metadata.

**Responses:** `200 { user }` on success; `200 { user, warning }` if display_name was set but metadata sync was not explicit; `400`/`405`/`500` with `{ error }` on failure.

## Flutter integration

| Flow        | display_name format   | Sent to              |
|------------|------------------------|----------------------|
| User create | `"Surname, Forename"`  | create_user_admin    |
| User edit   | `"Surname, Forename"`  | update_user_admin    |

- **user_creation_screen** → `UserService.createUser` sends `display_name` (and `email_confirm: true`).
- **user_edit_screen** → `UserEditService.updateUser` sends `display_name` when saving (derived from surname + forename in the same format). No further client changes needed for auth display_name.
