from fastapi import APIRouter, Depends, Response, status

from app.core.dependencies import (
    get_auth_service,
    get_current_active_user,
)
from app.features.auth.application.schemas import (
    ApiSuccess,
    AuthLoginData,
    AuthLoginRequest,
    AuthRegisterRequest,
    GoogleLoginRequest,
    UserPublic,
)
from app.features.auth.application.service import AuthService

router = APIRouter(prefix="/auth")


@router.post(
    "/register",
    response_model=ApiSuccess[UserPublic],
    status_code=status.HTTP_201_CREATED,
    response_model_exclude_none=True,
)
def register(
    payload: AuthRegisterRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> ApiSuccess[UserPublic]:
    user = auth_service.register(
        email=payload.email,
        password=payload.password,
        name=payload.name,
    )
    return ApiSuccess(data=UserPublic.from_auth_user(user))


@router.post(
    "/login",
    response_model=ApiSuccess[AuthLoginData],
    response_model_exclude_none=True,
)
def login(
    payload: AuthLoginRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> ApiSuccess[AuthLoginData]:
    result = auth_service.authenticate_with_password(
        email=payload.email,
        password=payload.password,
    )
    return ApiSuccess(
        data=AuthLoginData(
            access_token=result.access_token,
            token_type=result.token_type,
            expires_in=result.expires_in,
            user=UserPublic.from_auth_user(result.user),
        )
    )


@router.post(
    "/google",
    response_model=ApiSuccess[AuthLoginData],
    response_model_exclude_none=True,
)
def login_with_google(
    payload: GoogleLoginRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> ApiSuccess[AuthLoginData]:
    result = auth_service.authenticate_with_google_id_token(payload.id_token)
    return ApiSuccess(
        data=AuthLoginData(
            access_token=result.access_token,
            token_type=result.token_type,
            expires_in=result.expires_in,
            user=UserPublic.from_auth_user(result.user),
        )
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(_: object = Depends(get_current_active_user)) -> Response:
    return Response(status_code=status.HTTP_204_NO_CONTENT)
