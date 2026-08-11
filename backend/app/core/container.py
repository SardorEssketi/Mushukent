from dataclasses import dataclass

from app.core.config import Settings, get_settings
from app.core.storage import ObjectStorage
from app.infrastructure.db.session import DatabaseSessionManager
from app.infrastructure.storage.r2 import build_object_storage


@dataclass(slots=True)
class AppContainer:
    """Application dependency container.

    This is intentionally minimal for the skeleton and acts as the single place
    to wire concrete infrastructure dependencies to interfaces.
    """

    settings: Settings
    db_session_manager: DatabaseSessionManager
    object_storage: ObjectStorage | None = None


def build_container() -> AppContainer:
    settings = get_settings()
    db_session_manager = DatabaseSessionManager(settings.database_url)
    object_storage = build_object_storage(settings)
    return AppContainer(
        settings=settings,
        db_session_manager=db_session_manager,
        object_storage=object_storage,
    )
