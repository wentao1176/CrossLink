from typing import Literal
from pydantic import BaseModel, EmailStr, Field, field_validator
class Register(BaseModel):
    username: str = Field(min_length=3,max_length=64,pattern=r"^[a-zA-Z0-9_]+$")
    email: EmailStr
    password: str = Field(min_length=10,max_length=128)
class DeviceInput(BaseModel):
    device_uuid: str = Field(min_length=8,max_length=128)
    device_name: str = Field(min_length=1,max_length=100)
    platform: Literal["windows","android","web","macos","linux","ios"]
    device_type: Literal["desktop","phone","tablet","web"] = "desktop"
    os_version: str = Field(default="",max_length=100)
    app_version: str = Field(default="0.1.0",max_length=40)
class Login(BaseModel):
    account: str = Field(min_length=1,max_length=254)
    password: str = Field(min_length=1,max_length=128)
    device: DeviceInput
class Refresh(BaseModel):
    refresh_token: str = Field(min_length=1,max_length=512)
class Rename(BaseModel):
    device_name: str = Field(min_length=1,max_length=100)
class SendMessage(BaseModel):
    target_device_id: str|None = Field(default=None,max_length=36)
    type: Literal["text","clipboard","url","notification","file","image"]
    payload: dict
    client_message_id: str|None = Field(default=None,min_length=1,max_length=128)
class TransferUpdate(BaseModel):
    status: Literal["downloading","completed","failed","cancelled"]
    progress: int = Field(ge=0,le=100)
