# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x | ✅ Active |

## Reporting a Vulnerability

If you discover a security vulnerability in Y2Notes, please report it responsibly:

1. **Do NOT** create a public GitHub issue for security vulnerabilities
2. Email **security@y2notes.app** (or contact the maintainer directly)
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will acknowledge receipt within **48 hours** and aim to resolve critical
vulnerabilities within **7 days**.

## Security Considerations

### Data Storage

- All note data is stored **locally** in the app's sandboxed Documents directory
- Files are plain JSON with base64-encoded `PKDrawing` data
- No encryption at rest (relies on iOS Data Protection)
- Backup files (`.bak`) contain the previous version of each data file

### Cloud Sync (Google Drive)

- OAuth 2.0 authentication via Google Sign-In
- Tokens are stored in the iOS Keychain
- Sync data is encrypted in transit (HTTPS/TLS)
- Google Drive files are subject to Google's security policies

### No Sensitive Data Collection

- No analytics or telemetry is collected
- No personal data is transmitted to third parties
- OCR processing is performed entirely on-device via Apple Vision
- No network requests are made except for Google Drive sync (when enabled)

### Dependencies

- The app has **zero third-party dependencies** — it uses only Apple frameworks:
  - SwiftUI, UIKit, PencilKit, Core Animation, Vision, PDFKit
- This eliminates supply-chain attack vectors

### Apple Pencil Data

- Pencil pressure, tilt, and azimuth data is processed locally by PencilKit
- No biometric or stylus-specific data is stored or transmitted

## Privacy Manifest

The app includes a `PrivacyInfo.xcprivacy` manifest declaring:
- No required reason APIs are used beyond standard system APIs
- No tracking or fingerprinting
- No data collection for advertising
