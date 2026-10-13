from fastapi import APIRouter, Body, Depends, HTTPException, Request, Response, status
from posthog import identify_context, new_context
from structlog import get_logger

from app.core.dependencies import (
    get_auth_service,
    get_current_active_user,
)
from app.features.auth.application.schemas import (
    ApiSuccess,
    AuthLoginData,
    AuthLoginRequest,
    AuthRegisterRequest,
    AuthRegisterResponse,
    ChangePasswordRequest,
    GoogleLoginRequest,
    LogoutRequest,
    RefreshTokenRequest,
    ResendVerificationRequest,
    ResendVerificationResponse,
    SignInMethods,
    UserPublic,
    VerificationTokenData,
    VerifyEmailData,
    VerifyEmailRequest,
    VerifyEmailResponse,
)
from app.features.auth.application.service import AuthService
from app.features.auth.domain.models import AuthUser

router = APIRouter(prefix="/auth")
logger = get_logger(__name__)


def _identify_authenticated_user(
    request: Request,
    user: AuthUser,
    event: str | None = None,
    properties: dict[str, object] | None = None,
) -> None:
    """Identify successful auth transitions that lack a bearer-authenticated request."""
    posthog_client = getattr(request.app.state, "posthog_client", None)
    if posthog_client is None:
        return

    person_properties: dict[str, object] = {
        "email": user.email,
        "preferred_language": user.preferred_language,
        "is_moderator": user.is_moderator,
    }
    if user.name is not None:
        person_properties["name"] = user.name

    with new_context():
        identify_context(str(user.id))
        posthog_client.set(distinct_id=str(user.id), properties=person_properties)
        if event is not None:
            posthog_client.capture(event, properties=properties)


@router.get("/methods", response_model=ApiSuccess[SignInMethods])
def sign_in_methods(
    user=Depends(get_current_active_user),
    auth_service: AuthService = Depends(get_auth_service),
) -> ApiSuccess[SignInMethods]:
    return ApiSuccess(data=SignInMethods(**auth_service.get_sign_in_methods(user.id)))


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
def change_password(
    request: Request,
    payload: ChangePasswordRequest,
    user=Depends(get_current_active_user),
    auth_service: AuthService = Depends(get_auth_service),
) -> Response:
    auth_service.change_password(
        user.id, payload.current_password, payload.new_password, payload.confirm_password
    )
    posthog_client = getattr(request.app.state, "posthog_client", None)
    if posthog_client is not None:
        posthog_client.capture("password_changed")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/register",
    response_model=AuthRegisterResponse,
    status_code=status.HTTP_201_CREATED,
    response_model_exclude_none=True,
)
def register(
    request: Request,
    payload: AuthRegisterRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> AuthRegisterResponse:
    result = auth_service.register(
        email=payload.email,
        password=payload.password,
        name=payload.name,
        preferred_language=payload.preferred_language,
        accept_terms=payload.accept_terms,
        accept_privacy=payload.accept_privacy,
    )
    if result.user is not None:
        _identify_authenticated_user(request, result.user, event="user_registered")
    return ApiSuccess(
        data=VerificationTokenData(
            email=result.email,
            verification_required=result.verification_required,
            dev_verification_token=result.dev_verification_token,
        )
    )


@router.post(
    "/login",
    response_model=ApiSuccess[AuthLoginData],
    response_model_exclude_none=True,
)
def login(
    request: Request,
    payload: AuthLoginRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> ApiSuccess[AuthLoginData]:
    result = auth_service.authenticate_with_password(
        email=payload.email,
        password=payload.password,
    )
    _identify_authenticated_user(
        request,
        result.user,
        event="user_logged_in",
        properties={"login_method": "password"},
    )
    return ApiSuccess(
        data=AuthLoginData(
            access_token=result.access_token,
            refresh_token=result.refresh_token,
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
    request: Request,
    payload: GoogleLoginRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> ApiSuccess[AuthLoginData]:
    try:
        result = auth_service.authenticate_with_google_id_token(
            payload.id_token,
            accept_terms=payload.accept_terms,
            accept_privacy=payload.accept_privacy,
            password=payload.password,
        )
    except HTTPException as exc:
        detail = exc.detail if isinstance(exc.detail, dict) else {}
        error = detail.get("error") if isinstance(detail.get("error"), dict) else {}
        logger.info(
            "google_auth_rejected",
            provider="google",
            status_code=exc.status_code,
            error_code=error.get("code", "UNCLASSIFIED"),
        )
        raise
    _identify_authenticated_user(
        request,
        result.user,
        event="user_logged_in",
        properties={"login_method": "google"},
    )
    return ApiSuccess(
        data=AuthLoginData(
            access_token=result.access_token,
            refresh_token=result.refresh_token,
            token_type=result.token_type,
            expires_in=result.expires_in,
            user=UserPublic.from_auth_user(result.user),
        )
    )


@router.post(
    "/refresh",
    response_model=ApiSuccess[AuthLoginData],
    response_model_exclude_none=True,
)
def refresh(
    request: Request,
    payload: RefreshTokenRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> ApiSuccess[AuthLoginData]:
    result = auth_service.refresh_session(payload.refresh_token)
    _identify_authenticated_user(request, result.user)
    return ApiSuccess(
        data=AuthLoginData(
            access_token=result.access_token,
            refresh_token=result.refresh_token,
            token_type=result.token_type,
            expires_in=result.expires_in,
            user=UserPublic.from_auth_user(result.user),
        )
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    payload: LogoutRequest | None = Body(default=None),
    user=Depends(get_current_active_user),
    auth_service: AuthService = Depends(get_auth_service),
) -> Response:
    auth_service.revoke_refresh_session(
        payload.refresh_token if payload is not None else None,
        user_id=user.id,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/resend-verification",
    response_model=ResendVerificationResponse,
    response_model_exclude_none=True,
)
def resend_verification(
    payload: ResendVerificationRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> ResendVerificationResponse:
    token = auth_service.resend_verification(payload.email)
    return ApiSuccess(
        data=VerificationTokenData(
            email=payload.email,
            verification_required=True,
            dev_verification_token=token,
        )
    )


@router.post(
    "/verify-email",
    response_model=VerifyEmailResponse,
    response_model_exclude_none=True,
)
def verify_email(
    request: Request,
    payload: VerifyEmailRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> VerifyEmailResponse:
    user = auth_service.verify_email(payload.token)
    _identify_authenticated_user(request, user, event="email_verified")
    return ApiSuccess(
        data=VerifyEmailData(
            verified=True,
            email=user.email,
        )
    )
