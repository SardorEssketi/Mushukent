from __future__ import annotations

from datetime import datetime
from uuid import UUID

from geoalchemy2 import Geometry
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Computed,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import DOUBLE_PRECISION, ENUM, JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.infrastructure.db.base import Base
from app.infrastructure.db.enums import (
    CatStatus,
    LeaderboardType,
    PlaceCategory,
    PlaceSource,
    ReportStatus,
    ReportTargetType,
)
from app.infrastructure.db.mixins import (
    CreatedAtMixin,
    SoftDeleteMixin,
    TimestampMixin,
    UUIDPrimaryKeyMixin,
)

cat_status_enum = ENUM(
    CatStatus.HEALTHY.value,
    CatStatus.INJURED.value,
    CatStatus.NEEDS_HELP.value,
    CatStatus.ADOPTED.value,
    CatStatus.UNKNOWN.value,
    CatStatus.FEED.value,
    name="cat_status",
)

report_target_type_enum = ENUM(
    ReportTargetType.POST.value,
    ReportTargetType.COMMENT.value,
    ReportTargetType.USER.value,
    ReportTargetType.CAT.value,
    name="report_target_type",
)

report_status_enum = ENUM(
    ReportStatus.OPEN.value,
    ReportStatus.RESOLVED.value,
    ReportStatus.DISMISSED.value,
    name="report_status",
)

leaderboard_type_enum = ENUM(
    LeaderboardType.MOST_ACTIVE.value,
    LeaderboardType.MOST_POPULAR.value,
    LeaderboardType.TOP_HELPERS.value,
    name="leaderboard_type",
)

place_category_enum = ENUM(
    PlaceCategory.PET_SHOP.value,
    PlaceCategory.VETERINARY.value,
    PlaceCategory.SHELTER.value,
    name="place_category",
)

place_source_enum = ENUM(
    PlaceSource.OSM.value,
    PlaceSource.MANUAL.value,
    name="place_source",
)


class User(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    email_verified: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default=text("false"),
    )
    password_hash: Mapped[str | None] = mapped_column(Text, nullable=True)
    name: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    phone_number: Mapped[str | None] = mapped_column(Text, nullable=True)
    telegram_username: Mapped[str | None] = mapped_column(Text, nullable=True)
    preferred_language: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        default="en",
        server_default=text("'en'"),
    )
    allow_public_activity_view: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default=text("true"),
    )
    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    accepted_terms_version: Mapped[str | None] = mapped_column(Text, nullable=True)
    accepted_privacy_version: Mapped[str | None] = mapped_column(Text, nullable=True)
    accepted_legal_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default=text("true"),
    )
    is_moderator: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default=text("false"),
    )
    registered_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=text("now()"),
    )
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    created_cats: Mapped[list["Cat"]] = relationship(
        back_populates="creator",
        foreign_keys="Cat.created_by",
        passive_deletes=True,
    )
    posts: Mapped[list["Post"]] = relationship(back_populates="author", passive_deletes=True)
    comments: Mapped[list["Comment"]] = relationship(back_populates="author", passive_deletes=True)
    likes: Mapped[list["Like"]] = relationship(back_populates="user", passive_deletes=True)
    reports_created: Mapped[list["Report"]] = relationship(
        back_populates="reporter",
        foreign_keys="Report.reporter_id",
        passive_deletes=True,
    )
    reports_handled: Mapped[list["Report"]] = relationship(
        back_populates="handler",
        foreign_keys="Report.handled_by",
        passive_deletes=True,
    )
    lost_pets: Mapped[list["LostPet"]] = relationship(
        back_populates="author",
        passive_deletes=True,
    )
    adoption_posts: Mapped[list["AdoptionPost"]] = relationship(
        back_populates="author",
        passive_deletes=True,
    )

    __table_args__ = (
        CheckConstraint(
            "preferred_language IN ('en', 'uz', 'ru')",
            name="preferred_language_supported",
        ),
        Index("idx_users_registered_at", "registered_at"),
    )


class Cat(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "cats"

    name: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[CatStatus] = mapped_column(
        cat_status_enum,
        nullable=False,
        server_default=text("'unknown'"),
    )
    approximate_age_smallyears: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    created_by: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    first_seen_at: Mapped[datetime | None] = mapped_column(nullable=True)
    last_seen_at: Mapped[datetime | None] = mapped_column(nullable=True)
    cover_photo_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    canonical_location: Mapped[object | None] = mapped_column(
        Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=True,
    )
    total_observations: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )
    total_contributors: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )
    total_likes: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default=text("true"),
    )
    merged_into: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("cats.id", ondelete="SET NULL"),
        nullable=True,
    )

    creator: Mapped["User | None"] = relationship(back_populates="created_cats")
    merged_target: Mapped["Cat | None"] = relationship(
        remote_side="Cat.id",
        foreign_keys="Cat.merged_into",
    )
    posts: Mapped[list["Post"]] = relationship(back_populates="cat", passive_deletes=True)

    __table_args__ = (
        CheckConstraint(
            "approximate_age_smallyears IS NULL OR " "approximate_age_smallyears BETWEEN 0 AND 60",
            name="approximate_age_smallyears_range",
        ),
        CheckConstraint("merged_into IS NULL OR merged_into <> id", name="merged_into_not_self"),
        CheckConstraint("total_observations >= 0", name="total_observations_non_negative"),
        CheckConstraint("total_contributors >= 0", name="total_contributors_non_negative"),
        CheckConstraint("total_likes >= 0", name="total_likes_non_negative"),
        Index("cats_canonical_location_gist", "canonical_location", postgresql_using="gist"),
        Index("idx_cats_created_at", "created_at"),
    )


class Post(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "posts"

    cat_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("cats.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    photo_url: Mapped[str] = mapped_column(Text, nullable=False)
    thumb_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    location: Mapped[object] = mapped_column(
        Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=True,
    )
    latitude: Mapped[float | None] = mapped_column(
        DOUBLE_PRECISION,
        Computed("ST_Y(location::geometry)", persisted=True),
    )
    longitude: Mapped[float | None] = mapped_column(
        DOUBLE_PRECISION,
        Computed("ST_X(location::geometry)", persisted=True),
    )
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[CatStatus | None] = mapped_column(cat_status_enum, nullable=True)
    is_public: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default=text("true"),
    )
    like_count: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )
    comment_count: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )

    cat: Mapped["Cat"] = relationship(back_populates="posts")
    author: Mapped["User | None"] = relationship(back_populates="posts")
    photos: Mapped[list["PostPhoto"]] = relationship(
        back_populates="post",
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="PostPhoto.position",
    )
    comments: Mapped[list["Comment"]] = relationship(back_populates="post", passive_deletes=True)
    likes: Mapped[list["Like"]] = relationship(back_populates="post", passive_deletes=True)

    __table_args__ = (
        CheckConstraint("like_count >= 0", name="like_count_non_negative"),
        CheckConstraint("comment_count >= 0", name="comment_count_non_negative"),
        Index("posts_location_gist", "location", postgresql_using="gist"),
        Index("idx_posts_created_at", "created_at"),
        Index(
            "idx_posts_active_created_at",
            "created_at",
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("idx_posts_user_id", "user_id"),
        Index("idx_posts_cat_id", "cat_id"),
    )


class PostPhoto(UUIDPrimaryKeyMixin, CreatedAtMixin, Base):
    __tablename__ = "post_photos"

    post_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("posts.id", ondelete="CASCADE"),
        nullable=False,
    )
    photo_url: Mapped[str] = mapped_column(Text, nullable=False)
    thumb_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    position: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )

    post: Mapped["Post"] = relationship(back_populates="photos")

    __table_args__ = (
        CheckConstraint("position >= 0", name="post_photo_position_non_negative"),
        Index("idx_post_photos_post_id_position", "post_id", "position"),
    )


class Comment(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "comments"

    post_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("posts.id", ondelete="CASCADE"),
        nullable=True,
    )
    lost_pet_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("lost_pets.id", ondelete="CASCADE"),
        nullable=True,
    )
    adoption_post_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("adoption_posts.id", ondelete="CASCADE"),
        nullable=True,
    )
    user_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)

    post: Mapped["Post"] = relationship(back_populates="comments")
    lost_pet: Mapped["LostPet | None"] = relationship(back_populates="comments")
    adoption_post: Mapped["AdoptionPost | None"] = relationship(back_populates="comments")
    author: Mapped["User | None"] = relationship(back_populates="comments")

    __table_args__ = (
        CheckConstraint(
            "((post_id IS NOT NULL)::int + "
            "(lost_pet_id IS NOT NULL)::int + "
            "(adoption_post_id IS NOT NULL)::int) = 1",
            name="comments_exactly_one_target",
        ),
        Index("idx_comments_post_id", "post_id"),
        Index("idx_comments_lost_pet_id", "lost_pet_id"),
        Index("idx_comments_adoption_post_id", "adoption_post_id"),
        Index("idx_comments_user_id", "user_id"),
    )


class Like(UUIDPrimaryKeyMixin, CreatedAtMixin, Base):
    __tablename__ = "likes"

    post_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("posts.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    post: Mapped["Post"] = relationship(back_populates="likes")
    user: Mapped["User"] = relationship(back_populates="likes")

    __table_args__ = (
        UniqueConstraint("post_id", "user_id", name="uq_likes_post_id_user_id"),
        Index("idx_likes_post_id", "post_id"),
        Index("idx_likes_user_id", "user_id"),
    )


class UserBlock(UUIDPrimaryKeyMixin, CreatedAtMixin, Base):
    __tablename__ = "user_blocks"

    blocker_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    blocked_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    __table_args__ = (
        UniqueConstraint("blocker_id", "blocked_id", name="uq_user_blocks_blocker_blocked"),
        CheckConstraint("blocker_id <> blocked_id", name="user_blocks_not_self"),
        Index("idx_user_blocks_blocker_id", "blocker_id"),
        Index("idx_user_blocks_blocked_id", "blocked_id"),
    )


class Report(UUIDPrimaryKeyMixin, CreatedAtMixin, Base):
    __tablename__ = "reports"

    reporter_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    target_type: Mapped[ReportTargetType] = mapped_column(report_target_type_enum, nullable=False)
    target_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    metadata_json: Mapped[dict[str, object] | None] = mapped_column(
        "metadata",
        JSONB,
        nullable=True,
    )
    status: Mapped[ReportStatus] = mapped_column(
        report_status_enum,
        nullable=False,
        server_default=text("'open'"),
    )
    handled_by: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    handled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    reporter: Mapped["User | None"] = relationship(
        back_populates="reports_created",
        foreign_keys="Report.reporter_id",
    )
    handler: Mapped["User | None"] = relationship(
        back_populates="reports_handled",
        foreign_keys="Report.handled_by",
    )

    __table_args__ = (
        Index("idx_reports_status", "status"),
        Index("idx_reports_target", "target_type", "target_id"),
    )


class LeaderboardCache(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "leaderboard_cache"

    leaderboard_type: Mapped[LeaderboardType] = mapped_column(leaderboard_type_enum, nullable=False)
    period: Mapped[str] = mapped_column(Text, nullable=False)
    data: Mapped[dict[str, object]] = mapped_column(JSONB, nullable=False)
    computed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=text("now()"),
    )

    __table_args__ = (Index("idx_leaderboard_type_period", "leaderboard_type", "period"),)


class Place(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "places"

    name: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[PlaceCategory] = mapped_column(place_category_enum, nullable=False)
    location: Mapped[object] = mapped_column(
        Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=False,
    )
    latitude: Mapped[float | None] = mapped_column(
        DOUBLE_PRECISION,
        Computed("ST_Y(location::geometry)", persisted=True),
    )
    longitude: Mapped[float | None] = mapped_column(
        DOUBLE_PRECISION,
        Computed("ST_X(location::geometry)", persisted=True),
    )
    address: Mapped[str | None] = mapped_column(Text, nullable=True)
    phone: Mapped[str | None] = mapped_column(Text, nullable=True)
    phone_2: Mapped[str | None] = mapped_column(Text, nullable=True)
    instagram: Mapped[str | None] = mapped_column(Text, nullable=True)
    telegram: Mapped[str | None] = mapped_column(Text, nullable=True)
    website: Mapped[str | None] = mapped_column(Text, nullable=True)
    opening_hours: Mapped[str | None] = mapped_column(Text, nullable=True)
    days_off: Mapped[str | None] = mapped_column(Text, nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    source: Mapped[PlaceSource] = mapped_column(
        place_source_enum,
        nullable=False,
        server_default=text("'manual'"),
    )
    source_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default=text("true"),
    )

    category_links: Mapped[list["PlaceCategoryLink"]] = relationship(
        back_populates="place",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )

    __table_args__ = (
        Index("places_location_gist", "location", postgresql_using="gist"),
        Index("idx_places_category", "category"),
        Index("idx_places_source", "source", "source_id"),
        Index(
            "uq_places_source_source_id",
            "source",
            "source_id",
            unique=True,
            postgresql_where=text("source_id IS NOT NULL"),
        ),
    )


class PlaceCategoryLink(Base):
    __tablename__ = "place_category_links"

    place_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("places.id", ondelete="CASCADE"),
        primary_key=True,
        nullable=False,
    )
    category: Mapped[PlaceCategory] = mapped_column(
        place_category_enum,
        primary_key=True,
        nullable=False,
    )

    place: Mapped[Place] = relationship(back_populates="category_links")

    __table_args__ = (Index("idx_place_category_links_category", "category"),)


class LostPet(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "lost_pets"

    user_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    pet_name: Mapped[str] = mapped_column(Text, nullable=False)
    owner_phone_number: Mapped[str] = mapped_column(Text, nullable=False)
    owner_telegram_username: Mapped[str | None] = mapped_column(Text, nullable=True)
    owner_phone_publication_consent: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default=text("false"),
    )
    last_seen_location: Mapped[object] = mapped_column(
        Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=False,
    )
    last_seen_latitude: Mapped[float | None] = mapped_column(
        DOUBLE_PRECISION,
        Computed("ST_Y(last_seen_location::geometry)", persisted=True),
    )
    last_seen_longitude: Mapped[float | None] = mapped_column(
        DOUBLE_PRECISION,
        Computed("ST_X(last_seen_location::geometry)", persisted=True),
    )
    additional_info: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_resolved: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default=text("false"),
    )
    is_public: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default=text("true"),
    )
    comment_count: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )

    author: Mapped["User | None"] = relationship(back_populates="lost_pets")
    photos: Mapped[list["LostPetPhoto"]] = relationship(
        back_populates="lost_pet",
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="LostPetPhoto.position",
    )
    comments: Mapped[list["Comment"]] = relationship(
        back_populates="lost_pet",
        passive_deletes=True,
    )

    __table_args__ = (
        CheckConstraint("comment_count >= 0", name="lost_pets_comment_count_non_negative"),
        Index("lost_pets_last_seen_location_gist", "last_seen_location", postgresql_using="gist"),
        Index("idx_lost_pets_created_at", "created_at"),
        Index(
            "idx_lost_pets_active_created_at",
            "created_at",
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("idx_lost_pets_user_id", "user_id"),
    )


class LostPetPhoto(UUIDPrimaryKeyMixin, CreatedAtMixin, Base):
    __tablename__ = "lost_pet_photos"

    lost_pet_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("lost_pets.id", ondelete="CASCADE"),
        nullable=False,
    )
    photo_url: Mapped[str] = mapped_column(Text, nullable=False)
    thumb_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    position: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )

    lost_pet: Mapped["LostPet"] = relationship(back_populates="photos")

    __table_args__ = (
        CheckConstraint("position >= 0", name="lost_pet_photo_position_non_negative"),
        Index("idx_lost_pet_photos_lost_pet_id_position", "lost_pet_id", "position"),
    )


class AdoptionPost(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "adoption_posts"

    user_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    pet_name: Mapped[str] = mapped_column(Text, nullable=False)
    owner_phone_number: Mapped[str] = mapped_column(Text, nullable=False)
    owner_telegram_username: Mapped[str | None] = mapped_column(Text, nullable=True)
    owner_phone_publication_consent: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default=text("false"),
    )
    additional_info: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_public: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default=text("true"),
    )
    comment_count: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )

    author: Mapped["User | None"] = relationship(back_populates="adoption_posts")
    photos: Mapped[list["AdoptionPostPhoto"]] = relationship(
        back_populates="adoption_post",
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="AdoptionPostPhoto.position",
    )
    comments: Mapped[list["Comment"]] = relationship(
        back_populates="adoption_post",
        passive_deletes=True,
    )

    __table_args__ = (
        CheckConstraint("comment_count >= 0", name="adoption_posts_comment_count_non_negative"),
        Index("idx_adoption_posts_created_at", "created_at"),
        Index(
            "idx_adoption_posts_active_created_at",
            "created_at",
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("idx_adoption_posts_user_id", "user_id"),
    )


class AdoptionPostPhoto(UUIDPrimaryKeyMixin, CreatedAtMixin, Base):
    __tablename__ = "adoption_post_photos"

    adoption_post_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("adoption_posts.id", ondelete="CASCADE"),
        nullable=False,
    )
    photo_url: Mapped[str] = mapped_column(Text, nullable=False)
    thumb_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    position: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )

    adoption_post: Mapped["AdoptionPost"] = relationship(back_populates="photos")

    __table_args__ = (
        CheckConstraint("position >= 0", name="adoption_post_photo_position_non_negative"),
        Index(
            "idx_adoption_post_photos_post_id_position",
            "adoption_post_id",
            "position",
        ),
    )
