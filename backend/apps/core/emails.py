from __future__ import annotations

from dataclasses import dataclass
from html import escape

from django.conf import settings
from django.core.mail import EmailMultiAlternatives

from apps.core.locales import normalize_locale
from apps.notes.models import CollaboratorRole, ShareInvitation
from apps.users.models import Profile, User


@dataclass(frozen=True)
class MailCopy:
    subject: str
    eyebrow: str
    title: str
    body: str
    code_label: str = ""
    button_label: str = ""
    footer: str = ""


EMAIL_COPY = {
    "verification": {
        "en": MailCopy(
            subject="Your Safernotes verification code",
            eyebrow="Email verification",
            title="Your verification code",
            body="Enter this six-digit code in Safernotes to confirm your email address.",
            code_label="Verification code",
            footer="The code expires in 30 minutes. If you did not create this account, you can ignore this email.",
        ),
        "de": MailCopy(
            subject="Dein Safernotes Bestätigungscode",
            eyebrow="E-Mail-Bestätigung",
            title="Dein Bestätigungscode",
            body="Gib diesen sechsstelligen Code in Safernotes ein, um deine E-Mail-Adresse zu bestätigen.",
            code_label="Bestätigungscode",
            footer="Der Code läuft in 30 Minuten ab. Wenn du dieses Konto nicht erstellt hast, kannst du diese E-Mail ignorieren.",
        ),
    },
    "recovery": {
        "en": MailCopy(
            subject="Your Safernotes password reset code",
            eyebrow="Password reset",
            title="Reset your password",
            body="Use this six-digit code together with your recovery key to reset your Safernotes password.",
            code_label="Recovery code",
            footer="The code expires in 15 minutes. If you did not request a reset, you can ignore this email.",
        ),
        "de": MailCopy(
            subject="Dein Safernotes Code zum Zurücksetzen des Passworts",
            eyebrow="Passwortreset",
            title="Passwort zurücksetzen",
            body="Verwende diesen sechsstelligen Code zusammen mit deinem Recovery-Key, um dein Safernotes Passwort zurückzusetzen.",
            code_label="Wiederherstellungscode",
            footer="Der Code läuft in 15 Minuten ab. Wenn du keinen Reset angefordert hast, kannst du diese E-Mail ignorieren.",
        ),
    },
    "share_invitation_editor": {
        "en": MailCopy(
            subject="{sender} invited you to edit a note",
            eyebrow="Shared note",
            title="{sender} invited you to collaborate",
            body="You can now open Safernotes to review the invitation and edit the shared note.",
            button_label="Open Safernotes",
            footer="For your privacy, note contents are not shown in email.",
        ),
        "de": MailCopy(
            subject="{sender} hat dich eingeladen, eine Notiz zu bearbeiten",
            eyebrow="Geteilte Notiz",
            title="{sender} hat dich eingeladen",
            body="Öffne Safernotes, um die Einladung anzusehen und die geteilte Notiz gemeinsam zu bearbeiten.",
            button_label="Safernotes öffnen",
            footer="Zum Schutz deiner Privatsphäre werden Notizinhalte nicht per E-Mail angezeigt.",
        ),
    },
    "share_invitation_viewer": {
        "en": MailCopy(
            subject="{sender} invited you to view a note",
            eyebrow="Shared note",
            title="{sender} shared a note with you",
            body="You can now open Safernotes to review the invitation and view the shared note.",
            button_label="Open Safernotes",
            footer="For your privacy, note contents are not shown in email.",
        ),
        "de": MailCopy(
            subject="{sender} hat eine Notiz mit dir geteilt",
            eyebrow="Geteilte Notiz",
            title="{sender} hat eine Notiz mit dir geteilt",
            body="Öffne Safernotes, um die Einladung anzusehen und die geteilte Notiz zu betrachten.",
            button_label="Safernotes öffnen",
            footer="Zum Schutz deiner Privatsphäre werden Notizinhalte nicht per E-Mail angezeigt.",
        ),
    },
}


def user_locale(user: User) -> str:
    profile, _ = Profile.objects.get_or_create(user=user)
    return normalize_locale(profile.locale)


def send_verification_code_email(user: User, code: str) -> None:
    _send_code_email(user=user, code=code, template="verification")


def send_recovery_code_email(user: User, code: str) -> None:
    _send_code_email(user=user, code=code, template="recovery")


def send_share_invitation_email(invitation: ShareInvitation) -> None:
    role_template = (
        "share_invitation_editor"
        if invitation.role == CollaboratorRole.EDITOR
        else "share_invitation_viewer"
    )
    locale = user_locale(invitation.recipient_user)
    sender = invitation.sender_user.email
    copy = _copy(role_template, locale, sender=sender)
    app_url = getattr(settings, "APP_BASE_URL", "http://localhost:3000")
    plain = "\n\n".join(
        [
            copy.title,
            copy.body,
            app_url,
            copy.footer,
        ]
    )
    _send(
        to=invitation.recipient_user.email,
        subject=copy.subject,
        text_body=plain,
        html_body=_render_html(copy=copy, button_url=app_url),
    )


def _send_code_email(*, user: User, code: str, template: str) -> None:
    locale = user_locale(user)
    copy = _copy(template, locale)
    plain = "\n\n".join([copy.title, copy.body, f"{copy.code_label}: {code}", copy.footer])
    _send(
        to=user.email,
        subject=copy.subject,
        text_body=plain,
        html_body=_render_html(copy=copy, code=code),
    )


def _copy(template: str, locale: str, **format_values: str) -> MailCopy:
    base = EMAIL_COPY[template][normalize_locale(locale)]
    if not format_values:
        return base
    return MailCopy(
        subject=base.subject.format(**format_values),
        eyebrow=base.eyebrow.format(**format_values),
        title=base.title.format(**format_values),
        body=base.body.format(**format_values),
        code_label=base.code_label.format(**format_values),
        button_label=base.button_label.format(**format_values),
        footer=base.footer.format(**format_values),
    )


def _send(*, to: str, subject: str, text_body: str, html_body: str) -> None:
    message = EmailMultiAlternatives(
        subject=subject,
        body=text_body,
        from_email=None,
        to=[to],
    )
    message.attach_alternative(html_body, "text/html")
    message.send(fail_silently=True)


def _render_html(*, copy: MailCopy, code: str = "", button_url: str = "") -> str:
    escaped_code = escape(code)
    code_block = (
        f"""
          <div class="email-muted" style="margin:28px 0 8px;font-size:13px;line-height:20px;color:#64748b;">{escape(copy.code_label)}</div>
          <div class="email-code" style="letter-spacing:10px;font-size:34px;line-height:42px;font-weight:700;color:#0f172a;">{escaped_code}</div>
        """
        if code
        else ""
    )
    button = (
        f"""
          <div style="margin-top:28px;">
            <a class="email-button" href="{escape(button_url)}" style="display:inline-block;border-radius:10px;background:#1f2937;border:1px solid #1f2937;color:#ffffff;text-decoration:none;font-size:15px;font-weight:700;padding:13px 18px;">{escape(copy.button_label)}</a>
          </div>
        """
        if button_url and copy.button_label
        else ""
    )
    return f"""<!doctype html>
<html>
  <head>
    <meta name="color-scheme" content="light dark">
    <meta name="supported-color-schemes" content="light dark">
    <style>
      :root {{
        color-scheme: light dark;
        supported-color-schemes: light dark;
      }}
      @media (prefers-color-scheme: dark) {{
        .email-bg {{
          background: #0f172a !important;
        }}
        .email-card {{
          background: #111827 !important;
          border-color: #334155 !important;
        }}
        .email-title,
        .email-code {{
          color: #f8fafc !important;
        }}
        .email-body {{
          color: #cbd5e1 !important;
        }}
        .email-muted,
        .email-eyebrow,
        .email-footer,
        .email-brand {{
          color: #94a3b8 !important;
        }}
        .email-button {{
          background: #f8fafc !important;
          border-color: #f8fafc !important;
          color: #0f172a !important;
        }}
      }}
    </style>
  </head>
  <body class="email-bg" style="margin:0;background:#f8fafc;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f172a;">
    <div style="display:none;max-height:0;overflow:hidden;color:transparent;">{escape(copy.body)}</div>
    <table class="email-bg" role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f8fafc;">
      <tr>
        <td align="center" style="padding:36px 18px;">
          <table class="email-card" role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#ffffff;border:1px solid #e2e8f0;border-radius:18px;overflow:hidden;">
            <tr>
              <td style="padding:30px 32px 28px;">
                <div class="email-eyebrow" style="font-size:14px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;color:#64748b;">{escape(copy.eyebrow)}</div>
                <h1 class="email-title" style="margin:12px 0 0;font-size:28px;line-height:34px;font-weight:750;color:#0f172a;">{escape(copy.title)}</h1>
                <p class="email-body" style="margin:16px 0 0;font-size:16px;line-height:25px;color:#334155;">{escape(copy.body)}</p>
                {code_block}
                {button}
                <p class="email-footer" style="margin:30px 0 0;font-size:13px;line-height:20px;color:#64748b;">{escape(copy.footer)}</p>
              </td>
            </tr>
          </table>
          <div class="email-brand" style="margin-top:18px;font-size:12px;line-height:18px;color:#94a3b8;">Safernotes</div>
        </td>
      </tr>
    </table>
  </body>
</html>"""
