# CrossLink API v0.1
API base `/api/v1`, bearer access tokens on every protected REST route. See `/docs` for generated schema. Response errors are `{code,message,details}`; never parse raw HTML.

| Method | Path | Purpose |
|---|---|---|
| GET | /health | Database-aware health |
| POST | /auth/register | username, email, password (10–128 chars) |
| POST | /auth/login | account, password, device metadata; returns rotating session tokens |
| POST | /auth/refresh | refresh_token; atomically rotate token, reject replay |
| POST | /auth/logout | Revoke current session and websocket |
| GET | /users/me | Current account |
| GET/PATCH/DELETE | /devices, /devices/{id} | List, rename (`device_name`), revoke |
| POST | /messages | target_device_id (null broadcasts), type, payload, optional client_message_id |
| GET | /messages | Most recent device-visible messages; limit 1–500, before epoch seconds |
| GET | /messages/pending | Unacknowledged receipts for this device; limit 1–500 |
| POST | /messages/{id}/ack, /messages/{id}/read | Recipient-only, idempotent state advance |
| GET | /clipboard | Account clipboard history within retention |
| POST | /files/upload | Multipart file + optional target_device_id; automatically create message/transfers |
| GET | /files, /files/{id}/download | Account file history and authorized download; expired file returns 410 |
| GET/PATCH | /transfers, /transfers/{id} | History and recipient progress/status |

Supported types: text, clipboard, url, notification, file, image. Text payload `{content}`; notification adds `{title}`; URLs only http/https. Clipboard adds content_hash/origin_device_id/content_type on the server. File/image send uses existing `{file_id}` within account and retention. File upload returns id/name/size/mime_type/sha256/expires_at/message_id. Max 100 MiB per file, UTF-8 message content max 100 KiB. Binary download uses attachment and X-File-SHA256 headers. Files visible to devices of the same account, matching the design's account-ownership requirement. Broadcast recipients are snapshotted at send time; newly registered devices do not retroactively receive earlier broadcasts.

Per-device receipt states: pending → delivered → read. Sender history aggregates states across recipients; sending to no other device leaves sender history as sent. A websocket write does not mark delivered: only receiver ACK does. A repeated client_message_id must have identical type/target/payload or gets 409. History is capped to 100 entries in the client; server retains message records without a purge policy in this MVP.
