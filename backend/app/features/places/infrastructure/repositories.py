from __future__ import annotations

from typing import Any
from uuid import UUID

from geoalchemy2 import Geography
from sqlalchemy import cast, func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.features.cats.domain.models import GeoPoint
from app.features.places.domain.models import PlaceCategory, PlaceSource, PlaceSummary
from app.features.places.domain.repositories import PlaceListPage, PlaceRepository
from app.infrastructure.db.models import schema


class SqlAlchemyPlaceRepository(PlaceRepository):
    def __init__(self, session: Session) -> None:
        self.session = session

    def list_places(
        self,
        *,
        categories: list[PlaceCategory] | None,
        limit: int,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
        bbox: tuple[float, float, float, float] | None = None,
        map_only: bool = False,
    ) -> PlaceListPage:
        if map_only:
            statement = select(
                schema.Place.id,
                schema.Place.name,
                schema.Place.category,
                schema.Place.source,
                func.ST_X(schema.Place.location).label("longitude"),
                func.ST_Y(schema.Place.location).label("latitude"),
            ).where(schema.Place.is_active.is_(True))
        else:
            statement = (
                select(
                    schema.Place,
                    func.ST_X(schema.Place.location).label("longitude"),
                    func.ST_Y(schema.Place.location).label("latitude"),
                )
                .options(selectinload(schema.Place.category_links))
                .where(schema.Place.is_active.is_(True))
            )

        if categories:
            db_categories = [schema.PlaceCategory(category.value) for category in categories]
            statement = statement.where(
                or_(
                    schema.Place.category.in_(db_categories),
                    schema.Place.category_links.any(
                        schema.PlaceCategoryLink.category.in_(db_categories)
                    ),
                )
            )

        distance_expr = None
        if latitude is not None and longitude is not None and radius_meters is not None:
            reference_geom = func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326)
            statement = statement.where(
                schema.Place.location.op("&&")(
                    func.ST_Expand(reference_geom, radius_meters / 111_320.0)
                )
            )
            statement = statement.where(
                func.ST_DWithin(
                    cast(schema.Place.location, Geography),
                    cast(reference_geom, Geography),
                    radius_meters,
                )
            )
            distance_expr = func.ST_Distance(
                cast(schema.Place.location, Geography),
                cast(reference_geom, Geography),
            )
            statement = statement.add_columns(distance_expr.label("distance_meters"))
            statement = statement.order_by(distance_expr.asc(), schema.Place.name.asc())
        elif bbox is not None:
            min_lon, min_lat, max_lon, max_lat = bbox
            envelope = func.ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326)
            statement = statement.where(schema.Place.location.op("&&")(envelope))
            statement = statement.order_by(schema.Place.category.asc(), schema.Place.name.asc())
        else:
            statement = statement.order_by(schema.Place.category.asc(), schema.Place.name.asc())

        rows = self.session.execute(statement.limit(limit)).all()
        return PlaceListPage(
            items=[
                self._to_map_summary_row(row) if map_only else self._to_summary_row(row)
                for row in rows
            ],
            next_cursor=None,
            limit=limit,
        )

    def get_place(self, place_id: UUID) -> PlaceSummary | None:
        statement = (
            select(
                schema.Place,
                func.ST_X(schema.Place.location).label("longitude"),
                func.ST_Y(schema.Place.location).label("latitude"),
            )
            .options(selectinload(schema.Place.category_links))
            .where(schema.Place.id == place_id, schema.Place.is_active.is_(True))
        )
        row = self.session.execute(statement).first()
        return self._to_summary_row(row) if row is not None else None

    def _to_summary_row(self, row: Any) -> PlaceSummary:
        place = row[0]
        categories = sorted(
            [PlaceCategory(link.category) for link in place.category_links],
            key=_category_priority,
        )
        if not categories:
            categories = [PlaceCategory(place.category)]
        primary_category = _primary_category(categories)
        return PlaceSummary(
            id=place.id,
            name=place.name,
            category=primary_category,
            categories=categories,
            location=GeoPoint(latitude=float(row.latitude), longitude=float(row.longitude)),
            address=place.address,
            phone=place.phone,
            phone_2=place.phone_2,
            instagram=place.instagram,
            telegram=place.telegram,
            website=place.website,
            opening_hours=place.opening_hours,
            days_off=place.days_off,
            description=place.description,
            source=PlaceSource(place.source),
            source_id=place.source_id,
            verified_at=place.verified_at,
            distance_meters=getattr(row, "distance_meters", None),
        )

    @staticmethod
    def _to_map_summary_row(row: Any) -> PlaceSummary:
        category = PlaceCategory(row.category)
        return PlaceSummary(
            id=row.id,
            name=row.name,
            category=category,
            categories=[category],
            location=GeoPoint(latitude=float(row.latitude), longitude=float(row.longitude)),
            source=PlaceSource(row.source),
            distance_meters=getattr(row, "distance_meters", None),
        )


def _primary_category(categories: list[PlaceCategory]) -> PlaceCategory:
    return sorted(categories, key=_category_priority)[0]


def _category_priority(category: PlaceCategory) -> int:
    priority = {
        PlaceCategory.VETERINARY: 0,
        PlaceCategory.SHELTER: 1,
        PlaceCategory.PET_SHOP: 2,
    }
    return priority[category]
