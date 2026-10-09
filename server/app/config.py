from pathlib import Path
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file="/home/CrossLink/.env", extra="ignore")
    app_env: str = "development"
    database_url: str = "sqlite:////home/CrossLink/data/dev.db"
    jwt_secret: str = Field(min_length=32)
    access_token_expire: int = 1800
    refresh_token_expire: int = 2592000
    file_storage_path: Path = Path("/home/CrossLink/data/files")
    max_file_size: int = 100 * 1024 * 1024
    storage_min_free_bytes: int = Field(default=2 * 1024**3, ge=0)
    file_retention_seconds: int = 7 * 86400
    heartbeat_timeout: int = 90
    web_dist_path: Path = Path("/home/CrossLink/client/build/web")
