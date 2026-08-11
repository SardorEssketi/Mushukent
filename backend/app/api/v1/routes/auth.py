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
    AuthRegisterResponse,
    GoogleLoginRequest,
    ResendVerificationRequest,
    ResendVerificationResponse,
    UserPublic,
    VerificationTokenData,
    VerifyEmailData,
    VerifyEmailRequest,
    VerifyEmailResponse,
)
from app.features.auth.application.service import AuthService

router = APIRouter(prefix="/auth")


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
    result = auth_service.authenticate_with_google_id_token(
        payload.id_token,
        accept_terms=payload.accept_terms,
        accept_privacy=payload.accept_privacy,
    )
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
