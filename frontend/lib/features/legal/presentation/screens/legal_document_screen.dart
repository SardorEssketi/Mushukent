import 'package:flutter/material.dart';

enum LegalDocumentType {
  privacyPolicy,
  termsOfService,
}

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    required this.documentType,
    super.key,
  });

  final LegalDocumentType documentType;

  @override
  Widget build(BuildContext context) {
    final document = _documentFor(documentType);

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                document.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Effective date: ${document.version}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              for (final section in document.sections) ...[
                if (section.heading != null) ...[
                  Text(
                    section.heading!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                ],
                ...section.paragraphs.map(
                  (paragraph) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      paragraph,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            height: 1.35,
                          ),
                    ),
                  ),
                ),
                if (section.bullets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final bullet in section.bullets)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.check_circle_outline,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    bullet,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(height: 1.35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

_LegalDocument _documentFor(LegalDocumentType documentType) {
  switch (documentType) {
    case LegalDocumentType.privacyPolicy:
      return _privacyPolicy;
    case LegalDocumentType.termsOfService:
      return _termsOfService;
  }
}

class _LegalDocument {
  const _LegalDocument({
    required this.title,
    required this.version,
    required this.sections,
  });

  final String title;
  final String version;
  final List<_LegalSection> sections;
}

class _LegalSection {
  const _LegalSection({
    this.heading,
    this.paragraphs = const [],
    this.bullets = const [],
  });

  final String? heading;
  final List<String> paragraphs;
  final List<String> bullets;
}

const _termsOfService = _LegalDocument(
  title: 'Terms of Service',
  version: '2026-08-01',
  sections: [
    _LegalSection(
      paragraphs: [
        'By creating an account, you accept these Terms and the Privacy Policy.',
        'Mushukistan is a social platform and interactive map for street cats in Tashkent. It is not an emergency service, veterinary service, rescue organization, or government service.',
      ],
    ),
    _LegalSection(
      heading: 'Who operates Mushukistan',
      paragraphs: [
        'Mushukistan is operated by Sardor Muxtorov, an individual developer.',
        'Contact: sardor.datascience@gmail.com.',
      ],
    ),
    _LegalSection(
      heading: 'Eligibility',
      paragraphs: [
        'Eligibility: Users must be at least 16 years old or have legally valid parent/guardian consent.',
      ],
    ),
    _LegalSection(
      heading: 'Your account',
      paragraphs: [
        'You are responsible for your account credentials and for all content you submit.',
        'You may delete your account from Settings. You may also request deletion support by email at support@mushukistan.uz.',
      ],
    ),
    _LegalSection(
      heading: 'Your content',
      paragraphs: [
        'You may submit content only if you own it or have permission to use it. You grant Mushukistan a limited license to host, store, resize, display, transmit, moderate, remove, and otherwise use your content only to operate and improve the service.',
        "You remain responsible for making sure your content does not violate another person's privacy, copyright, trademark, publicity rights, or other rights.",
      ],
    ),
    _LegalSection(
      heading: 'Location and public information',
      paragraphs: [
        'Mushukistan uses location information for map, nearby cats, cat sightings, places, and lost-pet features.',
        'Some information you submit may be public, including cat photos, cat sighting descriptions, cat locations, comments, public profile summaries, lost-pet photos, lost-pet last-seen locations, and lost-pet phone numbers.',
        'Lost-pet posts may publish your profile phone number only after you explicitly confirm that it may be displayed publicly.',
      ],
    ),
    _LegalSection(
      heading: 'Prohibited conduct',
      bullets: [
        'Submit illegal, harmful, abusive, hateful, sexually explicit, exploitative, threatening, harassing, misleading, spam, malware, privacy-invasive, or copyright-infringing content.',
        "You must not publish another person's private information, image, phone number, address, or location without permission.",
        'Encourage animal cruelty or unsafe behavior.',
        "Interfere with Mushukistan's security, infrastructure, API, or moderation systems.",
        'Impersonate another person or misrepresent your connection to another person or organization.',
        'Use automated scraping, spam, or abusive automation.',
      ],
    ),
    _LegalSection(
      heading: 'Moderation and enforcement',
      paragraphs: [
        'Mushukistan may remove content, resolve reports, suspend users, or disable accounts to protect users, animals, the service, or legal compliance.',
        'Reports are reviewed within 7 days. Urgent safety, illegal-content, privacy, or animal-cruelty reports may be prioritized when feasible.',
      ],
    ),
    _LegalSection(
      heading: 'Copyright',
      paragraphs: [
        'You may upload only content that you own or are authorized to share. Copyright owners may request removal by contacting sardor.datascience@gmail.com.',
        'Accounts with 3 valid copyright strikes may be suspended or terminated. Appeals may be sent to sardor.datascience@gmail.com and are reviewed within 7 days.',
      ],
    ),
    _LegalSection(
      heading: 'Third-party services',
      paragraphs: [
        'Mushukistan may rely on third-party services for infrastructure, media storage, authentication, maps, and place data. These include DigitalOcean, Cloudflare R2 when configured, Google Sign-In when chosen by the user, and OpenStreetMap map/place data.',
      ],
    ),
    _LegalSection(
      heading: 'No warranties and liability',
      paragraphs: [
        'Mushukistan is provided as-is. Availability, map accuracy, place data, and user content are not guaranteed.',
        'To the maximum extent permitted by law, Mushukistan and its operator are not liable for indirect, incidental, consequential, special, punitive, or exemplary damages.',
      ],
    ),
    _LegalSection(
      heading: 'Governing law',
      paragraphs: [
        'These Terms are governed by the laws of the Republic of Uzbekistan.',
        'Any dispute shall be resolved by the competent courts of the Republic of Uzbekistan.',
      ],
    ),
  ],
);

const _privacyPolicy = _LegalDocument(
  title: 'Privacy Policy',
  version: '2026-08-01',
  sections: [
    _LegalSection(
      paragraphs: [
        'This Privacy Policy explains how Mushukistan collects, uses, stores, shares, and deletes personal data. It applies to the Mushukistan Android app and web app.',
      ],
    ),
    _LegalSection(
      heading: 'Who is responsible for your data',
      paragraphs: [
        'Operator/controller: Sardor Muxtorov, an individual developer.',
        'Contact: sardor.datascience@gmail.com.',
        'Mushukistan collects only the data needed to operate a social map for street cats in Tashkent.',
      ],
    ),
    _LegalSection(
      heading: 'Account data',
      bullets: [
        'Email address.',
        'Password hash for password accounts.',
        'Google Sign-In email/name when Google Sign-In is used.',
        'Registration time, last login time, preferred language, and accepted legal-document version.',
      ],
    ),
    _LegalSection(
      heading: 'Profile and content data',
      bullets: [
        'Name, avatar URL, phone number, bio, and public activity visibility preference.',
        'Cat sightings, cat photos, cat profile information, descriptions, comments, likes, reports, lost-pet posts, lost-pet photos, and lost-pet additional information.',
      ],
    ),
    _LegalSection(
      heading: 'Location and contact data',
      bullets: [
        'Current location when used for nearby search.',
        'Observation location when attached to a post.',
        'Cat canonical location, place-search location, and lost-pet last-seen location.',
        "Lost-pet posts publicly show the user's profile phone number only after explicit phone-publication consent.",
      ],
    ),
    _LegalSection(
      heading: 'Technical and security data',
      paragraphs: [
        'Mushukistan processes API request metadata used for authentication, rate limiting, abuse prevention, security, troubleshooting, and operational logs.',
        'Security and operational logs are kept for up to 90 days unless needed for security or legal reasons.',
      ],
    ),
    _LegalSection(
      heading: 'Photos and media',
      paragraphs: [
        'Photos are validated, resized, compressed, thumbnailed, and processed without preserving EXIF metadata.',
        'Binary image files are stored in Cloudflare R2 when configured, or in local media storage during development. PostgreSQL stores media URLs.',
      ],
    ),
    _LegalSection(
      heading: 'How Mushukistan uses data',
      bullets: [
        'Create and manage accounts.',
        'Authenticate users and verify email addresses.',
        'Publish and display user content.',
        'Show nearby cats, places, and map content.',
        'Operate lost-pet contact features.',
        'Enable comments, likes, reports, moderation, and account settings.',
        'Prevent abuse, rate-limit requests, secure the service, and comply with legal obligations.',
      ],
    ),
    _LegalSection(
      heading: 'Public information',
      paragraphs: [
        'Some information may be visible to other users or visitors, depending on the feature and account settings. Public information may include cat sightings, photos, descriptions, cat locations, comments, public profile summaries, lost-pet photos, lost-pet last-seen locations, and lost-pet phone numbers.',
      ],
    ),
    _LegalSection(
      heading: 'Third-party services',
      bullets: [
        'DigitalOcean for hosting and database infrastructure.',
        'Cloudflare R2 for uploaded media and object metadata when configured.',
        'Google when a user chooses Google Sign-In.',
        'OpenStreetMap for map tiles and map/place data.',
        'Email provider: not configured in the verified repository.',
        'Backup provider: not configured in the verified repository.',
      ],
    ),
    _LegalSection(
      heading: 'Cookies and browser storage',
      paragraphs: [
        'The Android app does not use cookies.',
        "The web app does not intentionally set advertising, analytics, or tracking cookies. The web app may use browser storage through the Flutter secure storage integration to keep the user's access token for authentication.",
      ],
    ),
    _LegalSection(
      heading: 'Retention and deletion',
      paragraphs: [
        'Active account and content data is retained while the account/content remains active.',
        'Account deletion anonymizes the account, disables login, deletes likes, removes profile personal data, hides and anonymizes user-owned posts/comments/lost-pet posts, removes copied lost-pet phone numbers, and attempts media cleanup.',
        'Mushukistan may retain limited records when necessary for legal compliance, security, fraud prevention, abuse prevention, copyright enforcement, or moderation audit purposes.',
        'Backups are not configured in the verified repository. If backups are enabled later, backup retention and hard-delete schedules must be documented before production release.',
      ],
    ),
    _LegalSection(
      heading: 'Your rights and choices',
      paragraphs: [
        'Users can delete their Mushukistan account directly inside the app: Settings -> About account -> Delete account.',
        'Users can also submit a deletion request by email: support@mushukistan.uz.',
        'Users may request access, correction, deletion, restriction, objection, portability, and withdrawal of consent where applicable by contacting: sardor.datascience@gmail.com.',
      ],
    ),
    _LegalSection(
      heading: 'International processing',
      paragraphs: [
        "Data may be processed outside the user's country by service providers such as DigitalOcean, Cloudflare, Google, and OpenStreetMap. Mushukistan should use provider data-processing terms or data-processing agreements where available.",
      ],
    ),
    _LegalSection(
      heading: 'Security',
      paragraphs: [
        'Mushukistan uses authentication, rate limiting, image validation, EXIF stripping, structured storage, and access controls to protect the service and user data. No system can be guaranteed completely secure.',
      ],
    ),
  ],
);
