from __future__ import annotations

import json
from html import escape as html_escape
from urllib import error, request
from urllib.parse import quote

from app.core.config import Settings
from app.core.security import api_error

RESEND_EMAILS_API_URL = "https://api.resend.com/emails"
RESEND_USER_AGENT = "mushukistan-backend/1.0"


class EmailVerificationSender:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def send_verification_email(self, *, email: str, token: str) -> None:
        if self.settings.app_env.casefold() == "development":
            return
        if (
            not self.settings.resend_api_key
            or not self.settings.resend_from_email
            or not self.settings.public_app_base_url
        ):
            raise api_error(
                500,
                "EMAIL_NOT_CONFIGURED",
                "Email verification is not configured.",
            )

        encoded_token = quote(token, safe="")
        verify_url = (
            f"{self.settings.public_app_base_url.rstrip('/')}/verify-email?token={encoded_token}"
        )
        escaped_verify_url = html_escape(verify_url, quote=True)
        expiration_hours = self.settings.email_verification_token_exp_hours
        hour_label = "hour" if expiration_hours == 1 else "hours"
        expiration_note = f"This link expires in {expiration_hours} {hour_label}."

        text = (
            "Mushukistan\n\n"
            "Verify your email\n\n"
            "Thanks for creating a Mushukistan account. Please verify your email address "
            "to finish setting up your account.\n\n"
            "Verify email address:\n"
            f"{verify_url}\n\n"
            f"{expiration_note}\n\n"
            "If you did not create this account, ignore this email."
        )
        html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="x-apple-disable-message-reformatting">
  <title>Verify your Mushukistan email</title>
  <style>
    @media only screen and (max-width: 600px) {{
      .email-shell {{ padding: 20px 12px !important; }}
      .email-content {{ padding: 30px 22px !important; }}
      .email-title {{ font-size: 27px !important; }}
    }}
  </style>
</head>
<body bgcolor="#FFF8F0"
      style="margin:0; padding:0; background-color:#FFF8F0;
             font-family:Arial, Helvetica, sans-serif; color:#2C2724;">
  <table role="presentation" width="100%" border="0" cellpadding="0"
         cellspacing="0" bgcolor="#FFF8F0"
         style="width:100%; background-color:#FFF8F0;">
    <tr>
      <td align="center" class="email-shell" style="padding:36px 16px;">
        <table role="presentation" width="600" border="0" cellpadding="0"
               cellspacing="0" bgcolor="#FFFCF7"
               style="width:100%; max-width:600px; background-color:#FFFCF7;
                      border:1px solid #E8DED4; border-radius:12px;">
          <tr>
            <td height="5" bgcolor="#C95F45"
                style="height:5px; line-height:5px; font-size:0;
                       background-color:#C95F45; border-radius:12px 12px 0 0;">&nbsp;</td>
          </tr>
          <tr>
            <td class="email-content" style="padding:40px 44px 36px;">
              <p style="margin:0 0 30px; color:#9D3F2D; font-size:18px;
                        line-height:26px; font-weight:700;">Mushukistan</p>
              <h1 class="email-title"
                  style="margin:0 0 16px; color:#2C2724; font-size:30px;
                         line-height:1.2; font-weight:700;">Verify your email</h1>
              <p style="margin:0 0 26px; color:#716861; font-size:16px;
                        line-height:25px;">Thanks for creating a Mushukistan account.
                Please verify your email address to finish setting up your account.</p>
              <table role="presentation" border="0" cellpadding="0" cellspacing="0"
                     style="margin:0 0 22px;">
                <tr>
                  <td align="center" bgcolor="#9D3F2D"
                      style="border-radius:8px; background-color:#9D3F2D;">
                    <a href="{escaped_verify_url}"
                       style="display:inline-block; padding:15px 24px;
                              border:1px solid #9D3F2D; border-radius:8px;
                              color:#FFFFFF; font-size:16px; line-height:20px;
                              font-weight:700; text-decoration:none;">Verify email address</a>
                  </td>
                </tr>
              </table>
              <p style="margin:0 0 12px; color:#716861; font-size:14px;
                        line-height:22px;">{expiration_note}</p>
              <p style="margin:0; color:#716861; font-size:14px; line-height:22px;">
                If you didn't create this account, you can ignore this email.</p>
              <table role="presentation" width="100%" border="0"
                     cellpadding="0" cellspacing="0"
                     style="width:100%; margin-top:28px;
                            border-top:1px solid #E8DED4;">
                <tr>
                  <td style="padding-top:20px;">
                    <p style="margin:0 0 8px; color:#716861; font-size:13px;
                              line-height:19px;">Button not working? Copy and paste this link:</p>
                    <p style="margin:0; color:#9D3F2D; font-size:13px;
                              line-height:20px; word-break:break-all;
                              word-wrap:break-word;">
                      <a href="{escaped_verify_url}"
                         style="color:#9D3F2D; text-decoration:underline;
                                word-break:break-all; word-wrap:break-word;">
                        {escaped_verify_url}</a>
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
        <p style="margin:18px 0 0; color:#716861; font-size:12px;
                  line-height:18px;">This is an automated account email from Mushukistan.</p>
      </td>
    </tr>
  </table>
</body>
</html>"""
        payload = {
            "from": self.settings.resend_from_email,
            "to": [email],
            "subject": "Verify your Mushukistan account",
            "text": text,
            "html": html,
        }
        data = json.dumps(payload).encode("utf-8")
        resend_request = request.Request(
            RESEND_EMAILS_API_URL,
            data=data,
            headers={
                "Authorization": f"Bearer {self.settings.resend_api_key}",
                "Content-Type": "application/json",
                "User-Agent": RESEND_USER_AGENT,
            },
            method="POST",
        )

        try:
            with request.urlopen(resend_request, timeout=10) as response:
                if response.status >= 400:
                    raise api_error(
                        502,
                        "EMAIL_DELIVERY_FAILED",
                        "Email verification could not be sent.",
                    )
        except error.HTTPError as exc:
            raise api_error(
                502,
                "EMAIL_DELIVERY_FAILED",
                "Email verification could not be sent.",
            ) from exc
        except error.URLError as exc:
            raise api_error(
                502,
                "EMAIL_DELIVERY_FAILED",
                "Email verification could not be sent.",
            ) from exc


class AccountDeletionConfirmationSender:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def send_confirmation_email(self, *, email: str, token: str) -> None:
        if self.settings.app_env.casefold() == "development":
            return
        if (
            not self.settings.resend_api_key
            or not self.settings.resend_from_email
            or not self.settings.public_app_base_url
        ):
            raise api_error(
                500,
                "EMAIL_NOT_CONFIGURED",
                "Account deletion email is not configured.",
            )

        confirm_url = (
            f"{self.settings.public_app_base_url.rstrip('/')}/delete-account?token={token}"
        )
        text = (
            "Open this link to confirm deletion of your Mushukistan account:\n\n"
            f"{confirm_url}\n\n"
            "After the page opens, press Confirm account deletion to complete deletion. "
            "This link is time-limited. If you did not request account deletion, "
            "ignore this email and your account will not be deleted."
        )
        payload = {
            "from": self.settings.resend_from_email,
            "to": [email],
            "subject": "Confirm deletion of your Mushukistan account",
            "text": text,
        }
        data = json.dumps(payload).encode("utf-8")
        resend_request = request.Request(
            RESEND_EMAILS_API_URL,
            data=data,
            headers={
                "Authorization": f"Bearer {self.settings.resend_api_key}",
                "Content-Type": "application/json",
                "User-Agent": RESEND_USER_AGENT,
            },
            method="POST",
        )

        try:
            with request.urlopen(resend_request, timeout=10) as response:
                if response.status >= 400:
                    raise api_error(
                        502,
                        "EMAIL_DELIVERY_FAILED",
                        "Account deletion email could not be sent.",
                    )
        except error.HTTPError as exc:
            raise api_error(
                502,
                "EMAIL_DELIVERY_FAILED",
                "Account deletion email could not be sent.",
            ) from exc
        except error.URLError as exc:
            raise api_error(
                502,
                "EMAIL_DELIVERY_FAILED",
                "Account deletion email could not be sent.",
            ) from exc
