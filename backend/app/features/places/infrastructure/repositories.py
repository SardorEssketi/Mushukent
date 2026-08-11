from __future__ import annotations

from typing import Any

from geoalchemy2 import Geography
from sqlalchemy import cast, func, select
from sqlalchemy.orm import Session

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
    ) -> PlaceListPage:
        statement = select(
            schema.Place.id,
            schema.Place.name,
            schema.Place.category,
            func.ST_X(schema.Place.location).label("longitude"),
            func.ST_Y(schema.Place.location).label("latitude"),
            schema.Place.address,
            schema.Place.phone,
            schema.Place.website,
            schema.Place.opening_hours,
            schema.Place.source,
            schema.Place.source_id,
            schema.Place.verified_at,
        ).where(schema.Place.is_active.is_(True))

        if categories:
            db_categories = [schema.PlaceCategory(category.value) for category in categories]
            statement = statement.where(schema.Place.category.in_(db_categories))

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
            items=[self._to_summary_row(row) for row in rows],
            next_cursor=None,
            limit=limit,
        )

    def _to_summary_row(self, row: Any) -> PlaceSummary:
        return PlaceSummary(
            id=row.id,
            name=row.name,
            category=PlaceCategory(row.category),
            location=GeoPoint(latitude=float(row.latitude), longitude=float(row.longitude)),
            address=row.address,
            phone=row.phone,
            website=row.website,
            opening_hours=row.opening_hours,
            source=PlaceSource(row.source),
            source_id=row.source_id,
            verified_at=row.verified_at,
            distance_meters=getattr(row, "distance_meters", None),
        )
