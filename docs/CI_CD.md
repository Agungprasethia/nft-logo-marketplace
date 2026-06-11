# CI/CD Implementation for NFT Marketplace

## Introduction
Continuous Integration and Continuous Deployment (CI/CD) is a set of practices that automate the processes of building, testing, and deploying software. By integrating these practices, development teams can deliver code changes more reliably and efficiently.

## Workflow Architecture
Our NFT Marketplace utilizes GitHub Actions to automate the CI/CD pipeline. 

```text
Developer
↓
GitHub Repository
↓
GitHub Actions
├─ Flutter Analyze
├─ Flutter Test
└─ Build APK
↓
Build Artifact
```

## How GitHub Actions Works
GitHub Actions is an automation platform integrated directly into GitHub. It allows us to define workflows using YAML files placed in the `.github/workflows` directory. 
When a specific event occurs (like a `push` or `pull_request` to the `main` branch), GitHub spins up a virtual environment (in this case, `ubuntu-latest`), sets up the required SDKs (like Java and Flutter), and runs a sequence of steps defined in the workflow file.

## Pipeline Steps
1. **Trigger**: The workflow is triggered automatically on pushes or pull requests to the `main` branch.
2. **Environment Setup**: A fresh `ubuntu-latest` runner is initialized and Java 17 is set up (required for Android builds).
3. **Flutter Setup**: The correct Flutter SDK is installed using `subosito/flutter-action`.
4. **Dependencies**: `flutter pub get` is run to fetch all project dependencies.
5. **Code Quality**: `flutter analyze` runs a static code analysis to enforce quality and catch potential issues early. The build will fail if any errors or warnings are found.
6. **Automated Testing**: `flutter test` executes the test suite to ensure the project logic is functioning as intended.
7. **APK Generation**: `flutter build apk --release` compiles the application into an Android Package (APK).
8. **Artifact Upload**: The generated APK is uploaded as an artifact (`app-release.apk`) to GitHub, making it readily downloadable without needing local compilation.

## Benefits for the NFT Marketplace Project
- **Automated Quality Assurance**: Ensures every code change meets strict quality standards (`flutter analyze` with 0 warnings/errors) and passes all tests before it is integrated.
- **Immediate Feedback**: Developers receive quick feedback on pull requests if their code breaks the build or introduces linting issues.
- **Easy Distribution**: The automated APK build means testers, lecturers, and stakeholders can easily download the latest release directly from the GitHub Actions tab without setting up a Flutter development environment.
- **DevOps Best Practices**: Implementing CI/CD brings the project closer to industry standards, an important aspect to demonstrate during the thesis presentation and defense.
