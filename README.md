# actions
A collection of helpful actions

## Usage

To use an action from this repo, add the following to your action file.

```yaml
- uses: actions/checkout@v3
  with:
    repository: BrunoB81HK/actions
    path: .github/helper-actions/
- uses: ./.github/helper-actions/<action>
  with:
    ...
```