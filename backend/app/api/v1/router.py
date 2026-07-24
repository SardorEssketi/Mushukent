from fastapi import APIRouter

from app.api.v1.routes.auth import router as auth_router
from app.api.v1.routes.cats import router as cats_router
from app.api.v1.routes.comments import router as comments_router
from app.api.v1.routes.feed import router as feed_router
from app.api.v1.routes.health import router as health_router
from app.api.v1.routes.leaderboards import router as leaderboards_router
from app.api.v1.routes.likes import router as likes_router
from app.api.v1.routes.moderation import router as moderation_router
from app.api.v1.routes.posts import router as posts_router
from app.api.v1.routes.reports import router as reports_router
from app.api.v1.routes.users import router as users_router

api_v1_router = APIRouter()
api_v1_router.include_router(health_router, tags=["health"])
api_v1_router.include_router(auth_router, tags=["auth"])
api_v1_router.include_router(users_router, tags=["users"])
api_v1_router.include_router(cats_router, tags=["cats"])
api_v1_router.include_router(posts_router, tags=["posts"])
api_v1_router.include_router(feed_router, tags=["feed"])
api_v1_router.include_router(comments_router, tags=["comments"])
api_v1_router.include_router(likes_router, tags=["likes"])
api_v1_router.include_router(leaderboards_router, tags=["leaderboards"])
api_v1_router.include_router(reports_router, tags=["reports"])
api_v1_router.include_router(moderation_router, tags=["moderation"])
