from fastapi import APIRouter, Body, Depends, HTTPException, Response, status
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
    ConnectGoogleRequest,
    GoogleLoginRequest,
    LogoutRequest,
    RefreshTokenRequest,
    ResendVerificationRequest,
    ResendVerificationResponse,
    SetPasswordRequest,
    SignInMethods,
    UserPublic,
    VerificationTokenData,
    VerifyEmailData,
    VerifyEmailRequest,
    VerifyEmailResponse,
)
from app.features.auth.application.service import AuthService

router = APIRouter(prefix="/auth")
logger = get_logger(__name__)


@router.get("/methods", response_model=ApiSuccess[SignInMethods])
def sign_in_methods(
    user=Depends(get_current_active_user),
    auth_service: AuthService = Depends(get_auth_service),
) -> ApiSuccess[SignInMethods]:
    return ApiSuccess(data=SignInMethods(**auth_service.get_sign_in_methods(user.id)))


@router.post("/set-password", status_code=status.HTTP_204_NO_CONTENT)
def set_password(
    payload: SetPasswordRequest,
    user=Depends(get_current_active_user),
    auth_service: AuthService = Depends(get_auth_service),
) -> Response:
    auth_service.set_password(user.id, payload.new_password, payload.confirm_password)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
def change_password(
    payload: ChangePasswordRequest,
    user=Depends(get_current_active_user),
    auth_service: AuthService = Depends(get_auth_service),
) -> Response:
    auth_service.change_password(
        user.id, payload.current_password, payload.new_password, payload.confirm_password
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/connect-google", status_code=status.HTTP_204_NO_CONTENT)
def connect_google(
    payload: ConnectGoogleRequest,
    user=Depends(get_current_active_user),
    auth_service: AuthService = Depends(get_auth_service),
) -> Response:
    auth_service.connect_google(user.id, payload.id_token)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/register",
    response_model=AuthRegisterResponse,
    status_code=status.HTTP_201_CREATED,
    response_model_exclude_none=True,
)
def register(
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
    return ApiSuccess(
        data=VerificationTokenData(
            email=result.user.email,
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
    payload: GoogleLoginRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> ApiSuccess[AuthLoginData]:
    try:
        result = auth_service.authenticate_with_google_id_token(
            payload.id_token,
            accept_terms=payload.accept_terms,
            accept_privacy=payload.accept_privacy,
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
    payload: RefreshTokenRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> ApiSuccess[AuthLoginData]:
    result = auth_service.refresh_session(payload.refresh_token)
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
    payload: VerifyEmailRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> VerifyEmailResponse:
    user = auth_service.verify_email(payload.token)
    return ApiSuccess(
        data=VerifyEmailData(
            verified=True,
            email=user.email,
        )
    )
