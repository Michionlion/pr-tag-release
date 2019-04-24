# PR Tag Release Script

This is a simple bash script to generate a tag on a merged PR. A label is added
to the PR as well, the name, description, and color of which can be modified.
It also sets relevent environment variables so that a Travis release is easy.
See the included `.travis.yml` for an example.

The available configuration environment variables are shown below. Keep in mind
that the `PRERELEASE_REGEX` and `DRAFT_REGEX` are applied to the ***title*** of
the Pull Request, unlike the others, which apply to the body.

```bash
MERGE_COMMIT_REGEX=${MERGE_COMMIT_REGEX-"Merge pull request #([0-9]+)"}
PATCH_CHANGE_REGEX=${PATCH_CHANGE_REGEX-"This (PR|release) is an?( small| tiny)? (update|bugfix|change)"}
MINOR_CHANGE_REGEX=${MINOR_CHANGE_REGEX-"This (PR|release) is a (feature( update| change)?|big (update|change))"}
MAJOR_CHANGE_REGEX=${MAJOR_CHANGE_REGEX-"This (PR|release) (is a ((compatibility[ -])?breaking|major) (update|change)| breaks( backwards)? compatibility)"}
PRERELEASE_REGEX=${PRERELEASE_REGEX-"\[(PRE|WIP|PRERELEASE)\]"}
DRAFT_REGEX=${DRAFT_REGEX-"\[(WIP|DRAFT)\]"}
```

```bash
PATCH_LABEL_COLOR=${PATCH_LABEL_COLOR-"14a3bc"}
PATCH_LABEL_NAME=${PATCH_LABEL_NAME-"patch"}
PATCH_LABEL_DESC=${PATCH_LABEL_DESC-"This PR updates the patch version: v0.0.X"}

MINOR_LABEL_COLOR=${MINOR_LABEL_COLOR-"23e059"}
MINOR_LABEL_NAME=${MINOR_LABEL_NAME-"minor"}
MINOR_LABEL_DESC=${MINOR_LABEL_DESC-"This PR updates the minor version: v0.X.0"}

MAJOR_LABEL_COLOR=${MAJOR_LABEL_COLOR-"c60f7a"}
MAJOR_LABEL_NAME=${MAJOR_LABEL_NAME-"major"}
MAJOR_LABEL_DESC=${MAJOR_LABEL_DESC-"This PR updates the major version: vX.0.0"}
```

Including the below `yaml` in your `.travis.yml` and providing the
`$GITHUB_OAUTH_TOKEN` enviroment variable will enable auto-generated releases.

```yaml
after_success:
  - wget https://github.com/Michionlion/pr-tag-release/releases/latest/download/pr_tag_release.sh
  - source pr_tag_release.sh
deploy:
  provider: releases
  api_key: "$GITHUB_OAUTH_TOKEN"
  skip_cleanup: true
  on:
    branch: master
    condition: $DO_GITHUB_RELEASE = true
```
