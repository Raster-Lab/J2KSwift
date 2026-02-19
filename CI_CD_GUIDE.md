# CI/CD Documentation for J2KSwift

This document explains the Continuous Integration and Continuous Deployment (CI/CD) setup for the J2KSwift project.

## Overview

J2KSwift uses GitHub Actions for automated testing, code quality checks, documentation generation, and releases. All workflows are defined in the `.github/workflows/` directory.

## Workflows

### 1. Swift Build and Test (`swift-build-test.yml`)

**Purpose**: Ensures the code builds and all tests pass on multiple platforms.

**Triggers**:
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches
- Manual workflow dispatch

**Jobs**:
1. **Test on macOS**: Builds and tests on macOS 14 with Swift 6.2
2. **Test on Linux**: Builds and tests on Ubuntu with Swift 6.2 Docker container
3. **SwiftLint**: Runs code style checks

**What it validates**:
- Code compiles on macOS and Linux
- All tests pass
- Release builds work
- Code follows style guidelines

**Status Badge**:
```markdown
[![Swift Build](https://github.com/Raster-Lab/J2KSwift/actions/workflows/swift-build-test.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/swift-build-test.yml)
```

### 2. Code Quality (`code-quality.yml`)

**Purpose**: Comprehensive code quality and security checks.

**Triggers**:
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop` branches
- Manual workflow dispatch

**Jobs**:
1. **SwiftLint**: Detailed linting with report generation
2. **Security Audit**: Checks for vulnerable dependencies
3. **Code Coverage**: Measures test coverage
4. **Package Validation**: Validates Swift package structure

**Artifacts**:
- SwiftLint report (JSON)
- Code coverage report (LCOV format)

**Status Badge**:
```markdown
[![Code Quality](https://github.com/Raster-Lab/J2KSwift/actions/workflows/code-quality.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/code-quality.yml)
```

### 3. Documentation (`documentation.yml`)

**Purpose**: Generates and deploys API documentation to GitHub Pages.

**Triggers**:
- Push to `main` branch
- Version tags (e.g., `v1.1.0`)
- Manual workflow dispatch

**What it does**:
1. Generates DocC documentation for each module:
   - J2KCore
   - J2KCodec
   - J2KAccelerate
   - J2KFileFormat
   - JPIP
2. Creates an index page linking to all modules
3. Deploys to GitHub Pages

**Documentation URL**: https://raster-lab.github.io/J2KSwift/

**Prerequisites**:
- GitHub Pages must be enabled in repository settings
- Pages source should be set to "GitHub Actions"

**Status Badge**:
```markdown
[![Documentation](https://github.com/Raster-Lab/J2KSwift/actions/workflows/documentation.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/documentation.yml)
```

### 4. Release (`release.yml`)

**Purpose**: Automates the release process.

**Triggers**:
- Push of version tags (e.g., `v1.1.0`, `v1.2.0`)
- Manual workflow dispatch with tag input

**What it does**:
1. **Validate**: Runs full build and test suite
2. **Create Release**: Creates GitHub release with:
   - Extracted release notes from `RELEASE_NOTES_v*.md` files
   - Auto-generated release notes as fallback
   - Release assets (if any)
3. **Create Release Branch**: Automatically creates a `release/vX.Y.Z` branch from the tag, enabling hotfix support for each release

**Release Branches**:
- A `release/vX.Y.Z` branch is automatically created for every release (e.g., `release/v1.2.0`)
- If the branch already exists, the step is skipped
- CI workflows (CI, Code Quality, Swift Build and Test) run on `release/*` branches
- Hotfixes can be applied to release branches and cherry-picked back to `main`/`develop`

**Creating a Release**:
```bash
# 1. Update VERSION file
echo "1.2.0" > VERSION

# 2. Create release notes (optional)
cp RELEASE_NOTES.md RELEASE_NOTES_v1.2.0.md

# 3. Commit changes
git add VERSION RELEASE_NOTES_v1.2.0.md
git commit -m "Prepare v1.2.0 release"
git push

# 4. Create and push tag
git tag -a v1.2.0 -m "Release v1.2.0"
git push origin v1.2.0

# The workflow will automatically:
# - Create the GitHub release
# - Create a release/v1.2.0 branch
```

### 5. Create Release Branches (`create-release-branches.yml`)

**Purpose**: Creates tags and release branches for existing versions. Use this to retroactively create release branches for versions that were released before the automation was added.

**Triggers**:
- Manual workflow dispatch only

**Inputs**:
- `version`: A specific version (e.g., `v1.8.0`) or `all` to create branches for every version with a `RELEASE_NOTES_v*.md` file

**What it does**:
1. Discovers versions from `RELEASE_NOTES_v*.md` files (when `all` is selected)
2. Creates annotated tags for each version if they don't exist
3. Creates `release/vX.Y.Z` branches from the tags if they don't exist

**Usage**:
```bash
# Via GitHub CLI - create branches for all versions
gh workflow run create-release-branches.yml -f version=all

# Via GitHub CLI - create branch for a specific version
gh workflow run create-release-branches.yml -f version=v1.8.0
```

Or trigger from the GitHub Actions UI: Actions → Create Release Branches → Run workflow.

## Dependabot Configuration

**File**: `.github/dependabot.yml`

**Purpose**: Automatically checks for dependency updates.

**Update Schedule**: Weekly (every Monday)

**What it monitors**:
1. GitHub Actions versions
2. Swift Package Manager dependencies

**Behavior**:
- Creates PRs for updates
- Labels PRs appropriately
- Limits to 5 open PRs per ecosystem

## Pull Request Template

**File**: `.github/pull_request_template.md`

**Purpose**: Standardizes PR descriptions with required sections:
- Description and motivation
- List of changes
- Testing performed
- Documentation updates
- Code quality checklist

## Issue Templates

### Bug Report (`bug_report.md`)
For reporting bugs with environment details, reproduction steps, and error output.

### Feature Request (`feature_request.md`)
For proposing new features with use cases and implementation considerations.

### Documentation (`documentation.md`)
For reporting documentation issues, errors, or improvements.

## Local Development Workflow

### Before Pushing

1. **Build the project**:
   ```bash
   swift build
   ```

2. **Run tests**:
   ```bash
   swift test
   ```

3. **Run SwiftLint** (if available):
   ```bash
   swiftlint lint
   ```

4. **Check package**:
   ```bash
   swift package describe
   ```

### Working with Branches

- `main`: Stable, production-ready code
- `develop`: Development branch for next release
- Feature branches: `feature/feature-name`
- Bug fixes: `fix/bug-description`
- Pull request branches: `copilot/description`

### Pull Request Process

1. Create a branch from `develop` (or `main` for hotfixes)
2. Make changes following code style guidelines
3. Add/update tests
4. Update documentation if needed
5. Push and create pull request
6. Wait for CI checks to pass
7. Address review comments
8. Merge after approval

## CI/CD Best Practices

### For Contributors

1. ✅ **Test locally first**: Run build and tests before pushing
2. ✅ **Fix SwiftLint issues**: Address linting warnings/errors
3. ✅ **Add tests**: Cover new code with tests
4. ✅ **Update docs**: Keep documentation in sync
5. ✅ **Small commits**: Make focused, reviewable changes

### For Maintainers

1. ✅ **Review CI results**: Check all workflows before merging
2. ✅ **Monitor coverage**: Maintain or improve test coverage
3. ✅ **Update dependencies**: Review and merge Dependabot PRs
4. ✅ **Release process**: Follow release checklist
5. ✅ **Documentation**: Keep docs updated on main branch

## Troubleshooting

### Workflow Fails on macOS

**Common Issues**:
- Swift version mismatch
- Xcode command line tools not configured
- Missing system dependencies

**Solution**: Check workflow logs for specific error messages.

### Workflow Fails on Linux

**Common Issues**:
- Platform-specific code (e.g., Apple frameworks)
- Missing Linux dependencies
- File path case sensitivity

**Solution**: Test in Swift Docker container locally:
```bash
docker run -v $PWD:/workspace swift:6.2 bash -c "cd /workspace && swift build && swift test"
```

### SwiftLint Failures

**Common Issues**:
- Code style violations
- Configuration errors in `.swiftlint.yml`

**Solution**:
```bash
# Run locally with same config
swiftlint lint

# Auto-fix some issues
swiftlint lint --fix
```

### Documentation Build Fails

**Common Issues**:
- Missing documentation comments on public APIs
- Invalid DocC syntax
- Build failures preventing doc generation

**Solution**: Ensure all public APIs have documentation:
```swift
/// Brief description.
///
/// Detailed description if needed.
///
/// - Parameter name: Description
/// - Returns: Description
/// - Throws: Error description
public func myFunction(name: String) throws -> Result {
    // ...
}
```

### Test Failures

**Common Issues**:
- Environment-specific failures
- Timing issues in async tests
- Resource file path issues

**Solution**: Check test logs and run locally:
```bash
# Run specific test
swift test --filter TestClassName.testMethodName

# Run with verbose output
swift test -v
```

## Monitoring and Maintenance

### Regular Tasks

1. **Weekly**: Review Dependabot PRs
2. **Per PR**: Check CI status before merging
3. **Per Release**: Verify all workflows pass
4. **Monthly**: Review code coverage trends
5. **Quarterly**: Update workflow versions

### Metrics to Track

- ✅ Build success rate
- ✅ Test pass rate (currently 98.3%)
- ✅ Code coverage percentage
- ✅ SwiftLint violation count
- ✅ Average PR merge time

## Future Improvements

Potential enhancements to consider:

1. **Performance Testing**: Add benchmark workflow
2. **Security Scanning**: Integrate SAST tools
3. **Automated Releases**: Semantic release automation
4. **Codecov Integration**: Upload coverage to Codecov
5. **Matrix Testing**: Test on multiple Swift versions
6. **Nightly Builds**: Daily builds of develop branch
7. **Package Registry**: Publish to package registries

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Swift Package Manager](https://swift.org/package-manager/)
- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)
- [DocC Documentation](https://www.swift.org/documentation/docc/)

## Support

If you encounter issues with CI/CD:

1. Check workflow logs in GitHub Actions tab
2. Search existing issues
3. Create a bug report with workflow logs
4. Tag maintainers if urgent

---

**Last Updated**: February 15, 2026  
**CI/CD Version**: 1.0  
**Maintained By**: J2KSwift Team
