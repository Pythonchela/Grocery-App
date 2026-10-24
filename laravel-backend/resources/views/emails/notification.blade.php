<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $headline }}</title>
</head>
<body style="margin:0;padding:0;background:#f5f4f0;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1a1a1a;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f4f0;padding:24px 12px;">
        <tr>
            <td align="center">
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:12px;">
                    <tr>
                        <td style="padding:24px 28px 8px;font-size:13px;font-weight:700;letter-spacing:.04em;color:#6b6b6b;">
                            {{ strtoupper($appName) }}
                        </td>
                    </tr>
                    <tr>
                        <td style="padding:8px 28px 4px;font-size:20px;line-height:1.3;font-weight:700;">
                            {{ $headline }}
                        </td>
                    </tr>
                    @if ($body)
                        <tr>
                            <td style="padding:8px 28px 4px;font-size:15px;line-height:1.55;color:#333333;">
                                {{ $body }}
                            </td>
                        </tr>
                    @endif
                    @if ($storeUrl)
                        <tr>
                            <td style="padding:20px 28px 8px;">
                                <a href="{{ $storeUrl }}" style="display:inline-block;background:#1a1a1a;color:#ffffff;text-decoration:none;font-weight:700;font-size:14px;padding:11px 22px;border-radius:999px;">
                                    Open {{ $appName }}
                                </a>
                            </td>
                        </tr>
                    @endif
                    <tr>
                        <td style="padding:20px 28px 24px;font-size:12px;line-height:1.5;color:#8a8a8a;">
                            You are receiving this because you have an account with {{ $appName }}.
                            You can turn these emails off in your notification settings.
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
