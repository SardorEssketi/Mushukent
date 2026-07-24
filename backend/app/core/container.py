from dataclasses import dataclass

from app.core.config import Settings, get_settings
from app.infrastructure.db.session import DatabaseSessionManager


@dataclass(slots=True)
class AppContainer:
    """Application dependency container.

    This is intentionally minimal for the skeleton and acts as the single place
    to wire concrete infrastructure dependencies to interfaces.
    """

    settings: Settings
    db_session_manager: DatabaseSessionManager


def build_container() -> AppContainer:
    settings = get_settings()
    db_session_manager = DatabaseSessionManager(settings.database_url)
    return AppContainer(settings=settings, db_session_manager=db_session_manager)
