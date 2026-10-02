import 'dart:convert';
import '../version.dart';

String renderCi(
    {required List<String> platforms,
    String flutterVersion = 'stable',
    String? wifProvider,
    String? serviceAccount,
    String? signingGitUrl}) {
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(flutterVersion)) {
    throw ArgumentError('Invalid Flutter Git ref');
  }
  if ((wifProvider == null) != (serviceAccount == null)) {
    throw ArgumentError(
        'WIF provider and service account must be supplied together');
  }
  final out = StringBuffer(r'''name: Torchinlane release
on:
  workflow_dispatch:
    inputs:
      target:
        type: choice
        options: [internal, production]
        default: internal
      upload_store:
        type: boolean
        default: true
permissions:
  contents: read
  id-token: write
concurrency:
  group: torchinlane-release
  cancel-in-progress: false
jobs:
''');
  for (final platform in platforms) {
    if (!['ios', 'android'].contains(platform)) {
      throw ArgumentError('Invalid CI platform');
    }
    out.writeln('  $platform:');
    out.writeln(
        '    runs-on: ${platform == 'ios' ? 'macos-latest' : 'ubuntu-latest'}');
    out.writeln('    timeout-minutes: 60');
    out.write(r'''    env:
      CI: 'true'
      TORCHINLANE_SKIP_VERSION_CHECK: '1'
    steps:
      - uses: actions/checkout@v7
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
      - name: Install Flutter and deployment tools
        shell: bash
        run: |
''');
    out.writeln(
        '          git clone --depth 1 --branch $flutterVersion https://github.com/flutter/flutter.git "\$RUNNER_TEMP/flutter"');
    out.write(r'''          echo "$RUNNER_TEMP/flutter/bin" >> "$GITHUB_PATH"
          echo "$HOME/.pub-cache/bin" >> "$GITHUB_PATH"
          export PATH="$RUNNER_TEMP/flutter/bin:$HOME/.pub-cache/bin:$PATH"
          flutter --version
''');
    out.writeln(
        '          dart pub global activate torchinlane $packageVersion');
    out.writeln(
        '          gem install fastlane${platform == 'ios' ? ' cocoapods' : ''} --no-document');
    out.write(r'''          torchinlane update -y
''');
    if (platform == 'android') {
      out.write(r'''      - name: Restore Android upload signing
        shell: bash
        env:
          KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
          KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
        run: |
          python3 - <<'PY'
          import base64, os, pathlib
          required = ['KEYSTORE_BASE64', 'KEYSTORE_PASSWORD', 'KEY_PASSWORD', 'KEY_ALIAS']
          if any(not os.environ.get(k) for k in required):
              raise SystemExit('Configure Android signing secrets first (doc/automation.md).')
          root = pathlib.Path('.torchinlane')
          root.mkdir(exist_ok=True)
          key = root / 'upload-keystore.jks'
          key.write_bytes(base64.b64decode(os.environ['KEYSTORE_BASE64']))
          key.chmod(0o600)
          def escape(value):
              return value.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace('=', '\\=').replace(':', '\\:')
          values = {'storePassword': os.environ['KEYSTORE_PASSWORD'], 'keyPassword': os.environ['KEY_PASSWORD'],
                    'keyAlias': os.environ['KEY_ALIAS'], 'storeFile': str(key.resolve())}
          properties = pathlib.Path('android/key.properties')
          properties.write_text('\n'.join(k + '=' + escape(v) for k, v in values.items()) + '\n')
          properties.chmod(0o600)
          PY
          torchinlane signing android --keystore .torchinlane/upload-keystore.jks --alias "$KEY_ALIAS"
''');
      // Authenticate immediately before deploy, after tools/signing setup.
      if (wifProvider != null) {
        out.write(
            '      - uses: google-github-actions/auth@v3\n        with:\n');
        out.writeln(
            '          workload_identity_provider: ${jsonEncode(wifProvider)}');
        out.writeln('          service_account: ${jsonEncode(serviceAccount)}');
        out.write(
            '          create_credentials_file: true\n          export_environment_variables: true\n');
      } else {
        out.write(r'''      - uses: google-github-actions/auth@v3
        with:
          credentials_json: ${{ secrets.GOOGLE_PLAY_CREDENTIALS_JSON }}
          create_credentials_file: true
          export_environment_variables: true
''');
      }
    } else {
      out.write(r'''      - name: Restore Apple API key
        shell: bash
        env:
          ASC_KEY_P8: ${{ secrets.ASC_KEY_P8 }}
        run: |
          test -n "$ASC_KEY_P8" || { echo 'Configure ASC_KEY_P8 secret first'; exit 1; }
          mkdir -p "$RUNNER_TEMP/torchinlane"
          printf '%s' "$ASC_KEY_P8" > "$RUNNER_TEMP/torchinlane/api_key.p8"
          chmod 600 "$RUNNER_TEMP/torchinlane/api_key.p8"
          echo "ASC_KEY_PATH=$RUNNER_TEMP/torchinlane/api_key.p8" >> "$GITHUB_ENV"
''');
      if (signingGitUrl != null) {
        out.write(r'''      - name: Install existing iOS signing identities
        env:
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
          MATCH_GIT_BASIC_AUTHORIZATION: ${{ secrets.MATCH_GIT_BASIC_AUTHORIZATION }}
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
        run: ''');
        out.writeln(
            'torchinlane signing sync --git-url ${_quote(signingGitUrl)}');
      } else {
        out.write(r'''      - name: Require iOS signing setup
        run: |
          echo 'Regenerate with --signing-git-url for fastlane match, or replace this step with your existing certificate/profile installation.'
          exit 1
''');
      }
    }
    out.write(r'''      - name: Verify app access and deploy
        shell: bash
        env:
          TARGET: ${{ inputs.target }}
          UPLOAD_STORE: ${{ inputs.upload_store }}
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
        run: |
''');
    out.writeln(
        '          torchinlane credentials verify --platform $platform');
    out.write(r'''          args=()
          if [ "$UPLOAD_STORE" = true ]; then args+=(--with-store); fi
''');
    out.writeln(
        '          torchinlane deploy --platform $platform --target "\$TARGET" --skip-credential-check "\${args[@]}"');
  }
  return out.toString();
}

String _quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
