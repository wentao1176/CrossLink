ALTER TABLE transfers ADD COLUMN IF NOT EXISTS message_id VARCHAR(36) REFERENCES messages(id);
UPDATE transfers AS t SET message_id = candidates.message_id
FROM (
 SELECT DISTINCT ON (t.id) t.id AS transfer_id, m.id AS message_id
 FROM transfers t JOIN messages m ON m.payload->>'file_id'=t.file_id AND m.sender_device_id=t.sender_device_id
 JOIN message_receipts r ON r.message_id=m.id AND r.device_id=t.target_device_id
 WHERE t.message_id IS NULL ORDER BY t.id,m.created_at,m.id
) AS candidates WHERE candidates.transfer_id=t.id;
