from __future__ import annotations

import argparse
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select

from app.core.config import get_settings
from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply Mushukistan retention cleanup.")
    parser.add_argument("--deleted-days", type=int, default=90)
    args = parser.parse_args()

    cutoff = datetime.now(UTC) - timedelta(days=args.deleted_days)
    settings = get_settings()
    db_session_manager = DatabaseSessionManager(settings.database_url)

    with db_session_manager.session_scope() as session:
        lost_pet_ids = session.scalars(
            select(schema.LostPet.id).where(schema.LostPet.deleted_at < cutoff)
        ).all()
        post_ids = session.scalars(
            select(schema.Post.id).where(schema.Post.deleted_at < cutoff)
        ).all()

        if lost_pet_ids:
            session.execute(
                delete(schema.LostPetPhoto).where(schema.LostPetPhoto.lost_pet_id.in_(lost_pet_ids))
            )
            session.execute(delete(schema.LostPet).where(schema.LostPet.id.in_(lost_pet_ids)))

        adoption_post_ids = session.scalars(
            select(schema.AdoptionPost.id).where(schema.AdoptionPost.deleted_at < cutoff)
        ).all()
        if adoption_post_ids:
            session.execute(
                delete(schema.AdoptionPostPhoto).where(
                    schema.AdoptionPostPhoto.adoption_post_id.in_(adoption_post_ids)
                )
            )
            session.execute(
                delete(schema.AdoptionPost).where(schema.AdoptionPost.id.in_(adoption_post_ids))
            )
        if post_ids:
            session.execute(delete(schema.Comment).where(schema.Comment.post_id.in_(post_ids)))
            session.execute(delete(schema.Like).where(schema.Like.post_id.in_(post_ids)))
            session.execute(delete(schema.Post).where(schema.Post.id.in_(post_ids)))
        session.execute(delete(schema.Comment).where(schema.Comment.deleted_at < cutoff))
        session.execute(delete(schema.Cat).where(schema.Cat.deleted_at < cutoff))

    print(f"Retention cleanup completed for records deleted before {cutoff.isoformat()}.")


if __name__ == "__main__":
    main()
