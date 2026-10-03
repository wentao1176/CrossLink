import time
import uuid
from sqlalchemy import String, Integer, BigInteger, Boolean, ForeignKey, JSON, UniqueConstraint, Index
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

def uid(): return str(uuid.uuid4())
def now(): return int(time.time())
class Base(DeclarativeBase): pass
class Identity:
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    created_at: Mapped[int] = mapped_column(BigInteger, default=now)
class User(Identity, Base):
    __tablename__="users"
    username: Mapped[str] = mapped_column(String(64), unique=True)
    email: Mapped[str] = mapped_column(String(254), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    status: Mapped[bool] = mapped_column(Boolean, default=True)
class Device(Identity, Base):
    __tablename__="devices"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    device_uuid: Mapped[str] = mapped_column(String(128), unique=True)
    device_name: Mapped[str] = mapped_column(String(100))
    device_type: Mapped[str] = mapped_column(String(20), default="desktop")
    platform: Mapped[str] = mapped_column(String(20))
    os_version: Mapped[str] = mapped_column(String(100), default="")
    app_version: Mapped[str] = mapped_column(String(40), default="0.1.0")
    last_seen: Mapped[int] = mapped_column(BigInteger, default=now)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)
class Session(Identity, Base):
    __tablename__="sessions"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"), index=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[int] = mapped_column(BigInteger)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)
class Message(Identity, Base):
    __tablename__="messages"
    __table_args__=(UniqueConstraint("sender_device_id","client_message_id"),)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    sender_device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"))
    target_device_id: Mapped[str|None] = mapped_column(ForeignKey("devices.id"), nullable=True)
    client_message_id: Mapped[str|None] = mapped_column(String(128), nullable=True)
    message_type: Mapped[str] = mapped_column(String(20))
    payload: Mapped[dict] = mapped_column(JSON)
class Receipt(Identity, Base):
    __tablename__="message_receipts"
    __table_args__=(UniqueConstraint("message_id","device_id"),Index("ix_pending","device_id","status"))
    message_id: Mapped[str] = mapped_column(ForeignKey("messages.id"))
    device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    delivered_at: Mapped[int|None] = mapped_column(BigInteger,nullable=True)
    read_at: Mapped[int|None] = mapped_column(BigInteger,nullable=True)
class File(Identity, Base):
    __tablename__="files"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    sender_device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"))
    original_name: Mapped[str] = mapped_column(String(255))
    storage_name: Mapped[str] = mapped_column(String(36))
    mime_type: Mapped[str] = mapped_column(String(255))
    size: Mapped[int] = mapped_column(BigInteger)
    sha256: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[int] = mapped_column(BigInteger,index=True)
class Transfer(Identity, Base):
    __tablename__="transfers"
    message_id: Mapped[str|None] = mapped_column(ForeignKey("messages.id"),nullable=True)
    file_id: Mapped[str] = mapped_column(ForeignKey("files.id"))
    sender_device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"))
    target_device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"),index=True)
    status: Mapped[str] = mapped_column(String(20),default="waiting")
    progress: Mapped[int] = mapped_column(Integer,default=0)
    completed_at: Mapped[int|None] = mapped_column(BigInteger,nullable=True)
class Clipboard(Identity, Base):
    __tablename__="clipboard_history"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"),index=True)
    device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"))
    content: Mapped[str] = mapped_column(String(102400))
    content_hash: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[int] = mapped_column(BigInteger)
