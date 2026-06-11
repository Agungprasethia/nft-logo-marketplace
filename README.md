# NFT Logo Marketplace

[![Flutter CI](https://github.com/Agungprasethia/nft-logo-marketplace/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/Agungprasethia/nft-logo-marketplace/actions/workflows/flutter-ci.yml)

A Flutter-based NFT Marketplace application designed to facilitate the buying, selling, and bidding of NFT Logos.

## CI/CD Pipeline

This project implements a professional CI/CD pipeline using GitHub Actions to ensure software quality and automate the build process.

- **Automated Analysis**: Every push and PR is checked using `flutter analyze` to guarantee 0 errors and 0 warnings.
- **Automated Testing**: Runs `flutter test` to ensure stability.
- **Automated Build**: Generates a release APK automatically.
- **Artifacts**: Download the latest `app-release.apk` directly from the [GitHub Actions tab](https://github.com/Agungprasethia/nft-logo-marketplace/actions).

Read more about the DevOps practices used in this project in the [CI/CD Documentation](docs/CI_CD.md).

## Getting Started

1. Ensure you have Flutter installed.
2. Clone this repository.
3. Run `flutter pub get` in the `mobile-app` directory.
4. Run `flutter run` to start the app.
